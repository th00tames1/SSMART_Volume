/*
 * Copyright 2014 Google Inc. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <tango-gl/conversions.h>
#include <tango-gl/gesture_camera.h>
#include <tango-gl/util.h>

#include <rtabmap/utilite/ULogger.h>
#include <rtabmap/utilite/UStl.h>
#include <rtabmap/utilite/UTimer.h>
#include <rtabmap/core/util3d_filtering.h>
#include <rtabmap/core/util3d_transforms.h>
#include <rtabmap/core/util3d_surface.h>
#include <pcl/common/transforms.h>
#include <pcl/common/common.h>
#include <opencv2/imgproc/imgproc.hpp> // cv::pointPolygonTest()
#include <cmath> // fabs, sqrt
#include <numeric> // std::accumulate

#include <glm/gtx/transform.hpp>

#include "scene.h"
#include "util.h"

// We want to represent the device properly with respect to the ground so we'll
// add an offset in z to our origin. We'll set this offset to 1.3 meters based
// on the average height of a human standing with a Tango device. This allows us
// to place a grid roughly on the ground for most users.
const glm::vec3 kHeightOffset = glm::vec3(0.0f, -1.3f, 0.0f);

// Color of the motion tracking trajectory.
const tango_gl::Color kTraceColor(0.66f, 0.66f, 0.66f);

// Color of the ground grid.
const tango_gl::Color kGridColor(0.85f, 0.85f, 0.85f);

// Frustum scale.
const glm::vec3 kFrustumScale = glm::vec3(0.4f, 0.3f, 0.5f);

const std::string kGraphVertexShader =
    "precision mediump float;\n"
    "precision mediump int;\n"
    "attribute vec3 vertex;\n"
    "uniform vec3 color;\n"
    "uniform mat4 mvp;\n"
    "varying vec3 v_color;\n"
    "void main() {\n"
    "  gl_Position = mvp*vec4(vertex.x, vertex.y, vertex.z, 1.0);\n"
    "  v_color = color;\n"
    "}\n";
const std::string kGraphFragmentShader =
    "precision mediump float;\n"
    "precision mediump int;\n"
    "varying vec3 v_color;\n"
    "void main() {\n"
    "  gl_FragColor = vec4(v_color.z, v_color.y, v_color.x, 1.0);\n"
    "}\n";

double totalVolume = 0.0;

Scene::Scene() :
        background_renderer_(0),
        gesture_camera_(0),
        axis_(0),
        frustum_(0),
        grid_(0),
        box_(0),
        trace_(0),
        graph_(0),
        graphVisible_(true),
        gridVisible_(true),
        traceVisible_(true),
        frustumVisible_(true),
        color_camera_to_display_rotation_(rtabmap::ROTATION_0),
        currentPose_(0),
        graph_shader_program_(0),
        blending_(true),
        mapRendering_(true),
        meshRendering_(true),
        meshRenderingTexture_(true),
        pointSize_(10.0f),
        boundingBoxRendering_(false),
        lighting_(false),
        backfaceCulling_(true),
        wireFrame_(false),
        r_(0.0f),
        g_(0.0f),
        b_(0.0f),
        fboId_(0),
        rboId_(0),
        screenWidth_(0),
        screenHeight_(0),
        doubleTapOn_(false),
        croppingOn_(false),
        lineWidth_(10.0f),
        polygonClosed_(false)
{
    depthTexture_ = 0;
    gesture_camera_ = new tango_gl::GestureCamera();
    gesture_camera_->SetCameraType(
          tango_gl::GestureCamera::kThirdPersonFollow);
}

Scene::~Scene() {
    DeleteResources();
    delete gesture_camera_;
    delete currentPose_;
}

//Should only be called in OpenGL thread!
void Scene::InitGLContent()
{
    if(axis_ != 0)
    {
        DeleteResources();
    }

    UASSERT(axis_ == 0);


    axis_ = new tango_gl::Axis();
    frustum_ = new tango_gl::Frustum();
    trace_ = new tango_gl::Trace();
    grid_ = new tango_gl::Grid();
    box_ = new BoundingBoxDrawable();


    axis_->SetScale(glm::vec3(0.5f,0.5f,0.5f));
    frustum_->SetColor(kTraceColor);
    trace_->ClearVertexArray();
    trace_->SetColor(kTraceColor);
    grid_->SetColor(kGridColor);
    grid_->SetPosition(kHeightOffset);
    box_->SetShader();
    box_->SetColor(1,0,0);

    PointCloudDrawable::createShaderPrograms();

    if(graph_shader_program_ == 0)
    {
        graph_shader_program_ = tango_gl::util::CreateProgram(kGraphVertexShader.c_str(), kGraphFragmentShader.c_str());
        UASSERT(graph_shader_program_ != 0);
    }
}

//Should only be called in OpenGL thread!
void Scene::DeleteResources() {

    LOGI("Scene::DeleteResources()");
    if(axis_)
    {
        delete axis_;
        axis_ = 0;
        delete frustum_;
        delete trace_;
        delete grid_;
        delete box_;
        delete background_renderer_;
        background_renderer_ = 0;
    }

    PointCloudDrawable::releaseShaderPrograms();

    if (graph_shader_program_) {
        glDeleteShader(graph_shader_program_);
        graph_shader_program_ = 0;
    }

    if(fboId_>0)
    {
        glDeleteFramebuffers(1, &fboId_);
        fboId_ = 0;
        glDeleteRenderbuffers(1, &rboId_);
        rboId_ = 0;
        glDeleteTextures(1, &depthTexture_);
        depthTexture_ = 0;
    }

    clear();
}

//Should only be called in OpenGL thread!
void Scene::clear()
{
    LOGI("Scene::clear()");
    for(std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.begin(); iter!=pointClouds_.end(); ++iter)
    {
        delete iter->second;
    }
    for(std::map<int, tango_gl::Axis*>::iterator iter=markers_.begin(); iter!=markers_.end(); ++iter)
    {
        delete iter->second;
    }
    if(trace_)
    {
        trace_->ClearVertexArray();
    }
    if(graph_)
    {
        delete graph_;
        graph_ = 0;
    }
    pointClouds_.clear();
    markers_.clear();
    if(grid_)
    {
        grid_->SetPosition(kHeightOffset);
    }
}

//Should only be called in OpenGL thread!
void Scene::SetupViewPort(int w, int h) {
    if (h == 0) {
        LOGE("Setup graphic height not valid");
    }
    
    UASSERT(gesture_camera_ != 0);
    gesture_camera_->SetWindowSize(static_cast<float>(w), static_cast<float>(h));
    glViewport(0, 0, w, h);
    if(screenWidth_ != w || screenHeight_ != h || fboId_ == 0)
    {
        UINFO("Setup viewport OpenGL: %dx%d", w, h);
        
        if(fboId_>0)
        {
            glDeleteFramebuffers(1, &fboId_);
            fboId_ = 0;
            glDeleteRenderbuffers(1, &rboId_);
            rboId_ = 0;
            glDeleteTextures(1, &depthTexture_);
            depthTexture_ = 0;
        }

        GLint originid = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &originid);
        
        // regenerate fbo texture
        // create a framebuffer object, you need to delete them when program exits.
        glGenFramebuffers(1, &fboId_);
        glBindFramebuffer(GL_FRAMEBUFFER, fboId_);

        // Create depth texture
        glGenTextures(1, &depthTexture_);
        glBindTexture(GL_TEXTURE_2D, depthTexture_);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glGenRenderbuffers(1, &rboId_);
        glBindRenderbuffer(GL_RENDERBUFFER, rboId_);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, w, h);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);

        // Set the texture to be at the color attachment point of the FBO (we pack depth 32 bits in color)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, depthTexture_, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rboId_);

        GLuint status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        UASSERT ( status == GL_FRAMEBUFFER_COMPLETE);
        glBindFramebuffer(GL_FRAMEBUFFER, originid);
    }
    screenWidth_ = w;
    screenHeight_ = h;
}

std::vector<glm::vec4> computeFrustumPlanes(const glm::mat4 & mat, bool normalize = true)
{
    // http://www.txutxi.com/?p=444
    std::vector<glm::vec4> planes(6);

    // Left Plane
    // col4 + col1
    planes[0].x = mat[0][3] + mat[0][0];
    planes[0].y = mat[1][3] + mat[1][0];
    planes[0].z = mat[2][3] + mat[2][0];
    planes[0].w = mat[3][3] + mat[3][0];

    // Right Plane
    // col4 - col1
    planes[1].x = mat[0][3] - mat[0][0];
    planes[1].y = mat[1][3] - mat[1][0];
    planes[1].z = mat[2][3] - mat[2][0];
    planes[1].w = mat[3][3] - mat[3][0];

    // Bottom Plane
    // col4 + col2
    planes[2].x = mat[0][3] + mat[0][1];
    planes[2].y = mat[1][3] + mat[1][1];
    planes[2].z = mat[2][3] + mat[2][1];
    planes[2].w = mat[3][3] + mat[3][1];

    // Top Plane
    // col4 - col2
    planes[3].x = mat[0][3] - mat[0][1];
    planes[3].y = mat[1][3] - mat[1][1];
    planes[3].z = mat[2][3] - mat[2][1];
    planes[3].w = mat[3][3] - mat[3][1];

    // Near Plane
    // col4 + col3
    planes[4].x = mat[0][3] + mat[0][2];
    planes[4].y = mat[1][3] + mat[1][2];
    planes[4].z = mat[2][3] + mat[2][2];
    planes[4].w = mat[3][3] + mat[3][2];

    // Far Plane
    // col4 - col3
    planes[5].x = mat[0][3] - mat[0][2];
    planes[5].y = mat[1][3] - mat[1][2];
    planes[5].z = mat[2][3] - mat[2][2];
    planes[5].w = mat[3][3] - mat[3][2];

    //if(normalize)
    {
        for(unsigned int i=0;i<planes.size(); ++i)
        {
            if(normalize)
            {
                float d = std::sqrt(planes[i].x * planes[i].x + planes[i].y * planes[i].y + planes[i].z * planes[i].z); // for normalizing the coordinates
                planes[i].x/=d;
                planes[i].y/=d;
                planes[i].z/=d;
                planes[i].w/=d;
            }
        }
    }

    return planes;
}

/**
 * Tells whether or not b is intersecting f.
 * http://www.txutxi.com/?p=584
 * @param planes Viewing frustum.
 * @param boxMin The axis aligned bounding box min.
 * @param boxMax The axis aligned bounding box max.
 * @return True if b intersects f, false otherwise.
 */
bool intersectFrustumAABB(
        const std::vector<glm::vec4> &planes,
        const pcl::PointXYZ &boxMin,
        const pcl::PointXYZ &boxMax)
{
  // Indexed for the 'index trick' later
    const pcl::PointXYZ * box[] = {&boxMin, &boxMax};

  // We only need to do 6 point-plane tests
  for (unsigned int i = 0; i < planes.size(); ++i)
  {
    // This is the current plane
    const glm::vec4 &p = planes[i];

    // p-vertex selection (with the index trick)
    // According to the plane normal we can know the
    // indices of the positive vertex
    const int px = p.x > 0.0f?1:0;
    const int py = p.y > 0.0f?1:0;
    const int pz = p.z > 0.0f?1:0;

    // Dot product
    // project p-vertex on plane normal
    // (How far is p-vertex from the origin)
    const float dp =
        (p.x*box[px]->x) +
        (p.y*box[py]->y) +
        (p.z*box[pz]->z) + p.w;

    // Doesn't intersect if it is behind the plane
    if (dp < 0) {return false; }
  }
  return true;
}

//Should only be called in OpenGL thread!
int Scene::Render(const float * uvsTransformed, glm::mat4 arViewMatrix, glm::mat4 arProjectionMatrix, const rtabmap::Mesh & occlusionMesh, bool mapping)
{
    UASSERT(gesture_camera_ != 0);

    if(currentPose_ == 0)
    {
        currentPose_ = new rtabmap::Transform(0,0,0,0,0,-M_PI/2.0f);
    }
    glm::vec3 position(currentPose_->x(), currentPose_->y(), currentPose_->z());
    Eigen::Quaternionf quat = currentPose_->getQuaternionf();
    glm::quat rotation(quat.w(), quat.x(), quat.y(), quat.z());
    glm::mat4 rotateM;
    if(!currentPose_->isNull())
    {
        rotateM = glm::rotate<float>(float(color_camera_to_display_rotation_)*-1.57079632679489661923132169163975144, glm::vec3(0.0f, 0.0f, 1.0f));

        if (gesture_camera_->GetCameraType() == tango_gl::GestureCamera::kFirstPerson)
        {
            // In first person mode, we directly control camera's motion.
            gesture_camera_->SetPosition(position);
            gesture_camera_->SetRotation(rotation*glm::quat(rotateM));
        }
        else
        {
            // In third person or top down mode, we follow the camera movement.
            gesture_camera_->SetAnchorPosition(position, rotation*glm::quat(rotateM));
        }
    }

    glm::mat4 projectionMatrix = gesture_camera_->GetProjectionMatrix();
    glm::mat4 viewMatrix = gesture_camera_->GetViewMatrix();

    bool renderBackgroundCamera =
            background_renderer_ &&
            gesture_camera_->GetCameraType() == tango_gl::GestureCamera::kFirstPerson &&
            !rtabmap::glmToTransform(arProjectionMatrix).isNull() &&
            uvsTransformed;

    if(renderBackgroundCamera)
    {
        if(projectionMatrix[0][0] > arProjectionMatrix[0][0]-0.3)
        {
            projectionMatrix = arProjectionMatrix;
            viewMatrix = arViewMatrix;
        }
        else
        {
            renderBackgroundCamera = false;
        }
    }

    rtabmap::Transform openglCamera = GetOpenGLCameraPose();//*rtabmap::Transform(0.0f, 0.0f, 3.0f, 0.0f, 0.0f, 0.0f);
    // transform in same coordinate as frustum filtering
    openglCamera *= rtabmap::Transform(
         0.0f,  0.0f,  1.0f, 0.0f,
         0.0f,  1.0f,  0.0f, 0.0f,
        -1.0f,  0.0f,  0.0f, 0.0f);

    //Culling
    std::vector<glm::vec4> planes = computeFrustumPlanes(projectionMatrix*viewMatrix, true);
    std::vector<PointCloudDrawable*> cloudsToDraw(pointClouds_.size());
    int oi=0;
    for(std::map<int, PointCloudDrawable*>::const_iterator iter=pointClouds_.begin(); iter!=pointClouds_.end(); ++iter)
    {
        if(!mapRendering_ && iter->first > 0)
        {
            break;
        }

        if(iter->second->isVisible())
        {
            if(intersectFrustumAABB(planes,
                    iter->second->aabbMinWorld(),
                    iter->second->aabbMaxWorld()))
            {
                cloudsToDraw[oi++] = iter->second;
            }
        }
    }
    cloudsToDraw.resize(oi);

    // First rendering to get depth texture
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDepthMask(GL_TRUE);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glDisable (GL_BLEND);
    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    if(backfaceCulling_)
    {
        glEnable(GL_CULL_FACE);
    }
    else
    {
        glDisable(GL_CULL_FACE);
    }

    bool onlineBlending =
        (!meshRendering_ &&
         occlusionMesh.cloud.get() &&
         occlusionMesh.cloud->size()) ||
        (blending_ &&
         gesture_camera_->GetCameraType()!=tango_gl::GestureCamera::kTopOrtho &&
         mapRendering_ && meshRendering_ &&
         (cloudsToDraw.size() > 1 || (renderBackgroundCamera && wireFrame_)));

    if(onlineBlending && fboId_)
    {
        GLint originid = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &originid);
        
        // set the rendering destination to FBO
        glBindFramebuffer(GL_FRAMEBUFFER, fboId_);

        glClearColor(0, 0, 0, 0);
        glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
        
        // Draw scene
        for(std::vector<PointCloudDrawable*>::const_iterator iter=cloudsToDraw.begin(); iter!=cloudsToDraw.end(); ++iter)
        {
            Eigen::Vector3f cloudToCamera(
                      (*iter)->getPose().x() - openglCamera.x(),
                      (*iter)->getPose().y() - openglCamera.y(),
                      (*iter)->getPose().z() - openglCamera.z());
            float distanceToCameraSqr = cloudToCamera[0]*cloudToCamera[0] + cloudToCamera[1]*cloudToCamera[1] + cloudToCamera[2]*cloudToCamera[2];
            (*iter)->Render(projectionMatrix, viewMatrix, meshRendering_, pointSize_, false, false, distanceToCameraSqr, 0, 0, 0, 0, 0, true);
        }
        
        if(!meshRendering_ && occlusionMesh.cloud.get() && occlusionMesh.cloud->size())
        {
            PointCloudDrawable drawable(occlusionMesh);
            drawable.Render(projectionMatrix, viewMatrix, true, pointSize_, false, false, 0, 0, 0, 0, 0, 0, true);
        }
        
        // back to normal window-system-provided framebuffer
        glBindFramebuffer(GL_FRAMEBUFFER, originid); // unbind
    }

    if(doubleTapOn_ && gesture_camera_->GetCameraType() != tango_gl::GestureCamera::kFirstPerson)
    {
        glClearColor(0, 0, 0, 0);
        glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);

        // FIXME: we could use the depthTexture if already computed!
        for(std::vector<PointCloudDrawable*>::const_iterator iter=cloudsToDraw.begin(); iter!=cloudsToDraw.end(); ++iter)
        {
            Eigen::Vector3f cloudToCamera(
                      (*iter)->getPose().x() - openglCamera.x(),
                      (*iter)->getPose().y() - openglCamera.y(),
                      (*iter)->getPose().z() - openglCamera.z());
            float distanceToCameraSqr = cloudToCamera[0]*cloudToCamera[0] + cloudToCamera[1]*cloudToCamera[1] + cloudToCamera[2]*cloudToCamera[2];
            
            (*iter)->Render(projectionMatrix, viewMatrix, meshRendering_, pointSize_*10.0f, false, false, distanceToCameraSqr, 0, 0, 0, 0, 0, true);
        }

        GLubyte zValue[4];
        glReadPixels(doubleTapPos_.x*screenWidth_, screenHeight_-doubleTapPos_.y*screenHeight_, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, zValue);
        float zValueF = float(zValue[0]/255.0f) + float(zValue[1]/255.0f)/255.0f + float(zValue[2]/255.0f)/65025.0f + float(zValue[3]/255.0f)/160581375.0f;

        if(zValueF != 0.0f)
        {
            zValueF = zValueF*2.0-1.0;//NDC
            glm::vec4 point = glm::inverse(projectionMatrix*viewMatrix)*glm::vec4(doubleTapPos_.x*2.0f-1.0f, (1.0f-doubleTapPos_.y)*2.0f-1.0f, zValueF, 1.0f);
            point /= point.w;
            
            if(croppingOn_ == true) {
                if(!std::isnan(point.x))
                {
                    // 새 마커를 찍을 때, "마커가 이미 3개 이상" + "첫 마커 재클릭 판별"
                    if(markerPoses_.size() >= 3)
                    {
                        float distSq = (markerPoses_.front().x() - point.x)*(markerPoses_.front().x() - point.x) +
                                       (markerPoses_.front().y() - point.y)*(markerPoses_.front().y() - point.y) +
                                       (markerPoses_.front().z() - point.z)*(markerPoses_.front().z() - point.z);
                        // 예: 30cm 이내면 같은 위치로 판단
                        if(distSq < 0.09f)
                        {
                            // 첫 마커를 재클릭 → 도형 닫힘
                            polygonClosed_ = true;
                            LOGI("Polygon closed!");

                            doubleTapOn_ = false;
                            return (int)cloudsToDraw.size();
                        }
                    }
                    // 위 조건에 걸리지 않으면, 평소처럼 새 마커 추가
                    static int markerId = 1;
                    rtabmap::Transform markerPose(point.x, point.y, point.z, 0, 0, 0);
                    addMarker2(markerId++, markerPose);
                }
            }
            else {
                gesture_camera_->SetAnchorOffset(glm::vec3(point.x, point.y, point.z) - position);
            }
            std::cout<< "mesh coordinate: " << point.x << ", " << point.y << ", " << point.z << std::endl;
        }
    }
    doubleTapOn_ = false;
    
    // ★★ polygon이 닫혔는지 확인
    if(polygonClosed_ && markerPoses_.size() >= 3)
    {
        LOGI("Polygon closed! We will filter all meshes inside polygon...");

        // 2D 폴리곤 좌표들
        std::vector<rtabmap::Transform> polygon2D = markerPoses_;

        // (A) createdMeshes_ 전체 순회 후 내부 필터링
        for(auto & kv : pointClouds_)
        {
            PointCloudDrawable * cloudDrawable = kv.second;
            if(cloudDrawable && cloudDrawable->hasMesh())
            {
                // 1) 가져오기
                rtabmap::Mesh mesh = cloudDrawable->getMesh();
                // 2) 필터링
                filterMeshInsidePolygon(polygon2D, mesh, cloudDrawable->getPose());
                // 3) 업데이트
                cloudDrawable->updateMesh(mesh);
                // 4) 볼륨 계산
                totalVolume = calculateMeshVolume(kv.first);
            }
        }
    }

    glClearColor(r_, g_, b_, 1.0f);
    glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
    
    if(renderBackgroundCamera && (!onlineBlending || !meshRendering_))
    {
        background_renderer_->Draw(uvsTransformed, 0, screenWidth_, screenHeight_, false);

        //To debug occlusion image:
        //PointCloudDrawable drawable(occlusionMesh);
        //drawable.Render(projectionMatrix, viewMatrix, true, pointSize_, false, false, 999.0f);
    }

    if(!currentPose_->isNull())
    {
        if (frustumVisible_ && gesture_camera_->GetCameraType() != tango_gl::GestureCamera::kFirstPerson)
        {
            frustum_->SetPosition(position);
            frustum_->SetRotation(rotation);
            // Set the frustum scale to 4:3, this doesn't necessarily match the physical
            // camera's aspect ratio, this is just for visualization purposes.
            frustum_->SetScale(kFrustumScale);
            frustum_->Render(projectionMatrix, viewMatrix);

            rtabmap::Transform cameraFrame = *currentPose_*rtabmap::optical_T_opengl*rtabmap::CameraMobile::opticalRotationInv;
            glm::vec3 positionCamera(cameraFrame.x(), cameraFrame.y(), cameraFrame.z());
            Eigen::Quaternionf quatCamera = cameraFrame.getQuaternionf();
            glm::quat rotationCamera(quatCamera.w(), quatCamera.x(), quatCamera.y(), quatCamera.z());

            axis_->SetPosition(positionCamera);
            axis_->SetRotation(rotationCamera);
            axis_->Render(projectionMatrix, viewMatrix);
        }

        trace_->UpdateVertexArray(position);
        if(traceVisible_)
        {
            trace_->Render(projectionMatrix, viewMatrix);
        }
        else
        {
            trace_->ClearVertexArray();
        }
    }

    if(gridVisible_ && !renderBackgroundCamera)
    {
        grid_->Render(projectionMatrix, viewMatrix);
    }

    if(graphVisible_ && graph_)
    {
        graph_->Render(projectionMatrix, viewMatrix);
    }

    if(onlineBlending)
    {
        glEnable (GL_BLEND);
        glDepthMask(GL_FALSE);
    }

    for(std::vector<PointCloudDrawable*>::const_iterator iter=cloudsToDraw.begin(); iter!=cloudsToDraw.end(); ++iter)
    {
        PointCloudDrawable * cloud = *iter;

        if(boundingBoxRendering_)
        {
            box_->updateVertices(cloud->aabbMinWorld(), cloud->aabbMaxWorld());
            box_->Render(projectionMatrix, viewMatrix);
        }

        Eigen::Vector3f cloudToCamera(
                cloud->getPose().x() - openglCamera.x(),
                cloud->getPose().y() - openglCamera.y(),
                cloud->getPose().z() - openglCamera.z());
        float distanceToCameraSqr = cloudToCamera[0]*cloudToCamera[0] + cloudToCamera[1]*cloudToCamera[1] + cloudToCamera[2]*cloudToCamera[2];

        cloud->Render(projectionMatrix, viewMatrix, meshRendering_, pointSize_, meshRenderingTexture_, lighting_, distanceToCameraSqr, onlineBlending?depthTexture_:0, screenWidth_, screenHeight_, gesture_camera_->getNearClipPlane(), gesture_camera_->getFarClipPlane(), false, wireFrame_);
    }

    if(onlineBlending)
    {
        if(renderBackgroundCamera && meshRendering_)
        {
            background_renderer_->Draw(uvsTransformed, depthTexture_, screenWidth_, screenHeight_, mapping);
        }
        
        glDisable (GL_BLEND);
        glDepthMask(GL_TRUE);
    }
    
    //=====================================================
    // (2) 마커(Axis) 렌더링
    for(std::map<int, tango_gl::Axis*>::const_iterator iter=markers_.begin();
        iter!=markers_.end();
        ++iter)
    {
        iter->second->Render(projectionMatrix, viewMatrix);
    }

    //=====================================================
    // (3) 마커 사이 선(Line) 렌더링
    if(markerPoses_.size() > 1)
    {
        glUseProgram(graph_shader_program_);

        // 원하는 선 색/두께
        GLint colorHandle = glGetUniformLocation(graph_shader_program_, "color");
        glUniform3f(colorHandle, 1.0f, 1.0f, 1.0f);
        glLineWidth(lineWidth_);

        // MVP
        GLint mvpHandle = glGetUniformLocation(graph_shader_program_, "mvp");
        glm::mat4 mvp = projectionMatrix * viewMatrix;
        glUniformMatrix4fv(mvpHandle, 1, GL_FALSE, glm::value_ptr(mvp));

        // VBO 구성
        std::vector<glm::vec3> lineVertices;
        lineVertices.reserve(markerPoses_.size());
        for(size_t i=0; i<markerPoses_.size(); ++i)
        {
            lineVertices.push_back(glm::vec3(markerPoses_[i].x(),
                                             markerPoses_[i].y(),
                                             markerPoses_[i].z()));
        }

        GLuint lineVBO = 0;
        glGenBuffers(1, &lineVBO);
        glBindBuffer(GL_ARRAY_BUFFER, lineVBO);
        glBufferData(GL_ARRAY_BUFFER,
                     lineVertices.size()*sizeof(glm::vec3),
                     lineVertices.data(),
                     GL_STATIC_DRAW);

        GLint vertexHandle = glGetAttribLocation(graph_shader_program_, "vertex");
        glEnableVertexAttribArray(vertexHandle);
        glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, 0);

        // i-> i+1 연결
        for(size_t i=0; i<lineVertices.size()-1; ++i)
        {
            glDrawArrays(GL_LINES, i, 2);
        }

        // polygonClosed_ == true면 "마지막 -> 첫 번째"도 연결
        if(polygonClosed_ && markerPoses_.size() >= 3)
        {
            glDrawArrays(GL_LINES, 0, 1);

            glm::vec3 lastPt = lineVertices.back();
            glm::vec3 firstPt = lineVertices.front();
            std::vector<glm::vec3> closedLine;
            closedLine.push_back(lastPt);
            closedLine.push_back(firstPt);

            GLuint closedLineVBO=0;
            glGenBuffers(1, &closedLineVBO);
            glBindBuffer(GL_ARRAY_BUFFER, closedLineVBO);
            glBufferData(GL_ARRAY_BUFFER,
                         closedLine.size()*sizeof(glm::vec3),
                         closedLine.data(),
                         GL_STATIC_DRAW);
            glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, 0);

            glDrawArrays(GL_LINES, 0, 2);

            // 정리
            glBindBuffer(GL_ARRAY_BUFFER, 0);
            glDeleteBuffers(1, &closedLineVBO);
        }

        glDisableVertexAttribArray(vertexHandle);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glDeleteBuffers(1, &lineVBO);

        glUseProgram(0);
    }
    return (int)cloudsToDraw.size();
}

void Scene::SetCameraType(tango_gl::GestureCamera::CameraType camera_type) {
  gesture_camera_->SetCameraType(camera_type);
}

void Scene::SetCameraPose(const rtabmap::Transform & pose)
{
    UASSERT(!pose.isNull());
    if(currentPose_ ==0)
    {
        currentPose_ = new rtabmap::Transform(0,0,0,0,0,-M_PI/2.0f);
    }
    *currentPose_ = pose;
}

void Scene::setFOV(float angle)
{
    gesture_camera_->SetFieldOfView(angle);
}
void Scene::setOrthoCropFactor(float value)
{
    gesture_camera_->SetOrthoCropFactor(value);
}
void Scene::setGridRotation(float angleDeg)
{
    float angleRad = angleDeg * DEGREE_2_RADIANS;
    if(grid_)
    {
        glm::quat rot = glm::rotate(glm::quat(1,0,0,0), angleRad, glm::vec3(0, 1, 0));
        grid_->SetRotation(rot);
    }
}

rtabmap::Transform Scene::GetOpenGLCameraPose(float * fov) const
{
    if(fov)
    {
        *fov = gesture_camera_->getFOV();
    }
    return rtabmap::glmToTransform(gesture_camera_->GetTransformationMatrix());
}

void Scene::OnTouchEvent(int touch_count,
                         tango_gl::GestureCamera::TouchEvent event, float x0,
                         float y0, float x1, float y1) {
    
    UASSERT(gesture_camera_ != 0);
    if(touch_count == 3)
    {
        //doubletap
        if(!doubleTapOn_)
        {
            doubleTapPos_.x = x0;
            doubleTapPos_.y = y0;
            doubleTapOn_ = true;
            
            //Cropping
            if(event == 7) {
                croppingOn_ = true;
            }
            else{
                croppingOn_ = false;
            }
        }
    }
    else
    {
        // rotate/translate/zoom
        gesture_camera_->OnTouchEvent(touch_count, event, x0, y0, x1, y1);
    }
}

void Scene::updateGraph(
        const std::map<int, rtabmap::Transform> & poses,
        const std::multimap<int, rtabmap::Link> & links)
{
    LOGI("updateGraph");
    //create
    UASSERT(graph_shader_program_ != 0);
    delete graph_;
    graph_ = new GraphDrawable(graph_shader_program_, poses, links);
}

void Scene::setGraphVisible(bool visible)
{
    graphVisible_ = visible;
}

void Scene::setGridVisible(bool visible)
{
    gridVisible_ = visible;
}

void Scene::setTraceVisible(bool visible)
{
    traceVisible_ = visible;
}

void Scene::setFrustumVisible(bool visible)
{
    frustumVisible_ = visible;
}

//Should only be called in OpenGL thread!
void Scene::addMarker(int id, const rtabmap::Transform & pose)
{
    std::map<int, tango_gl::Axis*>::iterator iter = markers_.find(id);
    if(iter != markers_.end())
    {
        delete iter->second;
        markers_.erase(iter);
    }

    tango_gl::Axis * drawable = new tango_gl::Axis();

    drawable->SetScale(glm::vec3(0.05f,0.05f,0.05f));
    drawable->SetLineWidth(5);
    markers_.insert(std::make_pair(id, drawable));

    // Pose 설정
    setMarkerPose(id, pose);

    // 순서/좌표 기록
    markerOrder_.push_back(id);
    markerPoses_.push_back(pose);

    LOGI("Added marker %d at pose (%f,%f,%f)",
         id, pose.x(), pose.y(), pose.z());
}

void Scene::addMarker2(int id, const rtabmap::Transform & pose)
{
    // 폴리곤이 이미 닫힌 상태면 더는 추가 불가
    if(polygonClosed_)
    {
        LOGI("Polygon is already closed. Ignoring new marker.");
        return;
    }

    std::map<int, tango_gl::Axis*>::iterator iter = markers_.find(id);
    if(iter != markers_.end())
    {
        delete iter->second;
        markers_.erase(iter);
    }

    tango_gl::Axis * drawable = new tango_gl::Axis();

    drawable->SetScale(glm::vec3(0.00f,0.2f,0.00f));
    drawable->SetLineWidth(10);
    markers_.insert(std::make_pair(id, drawable));

    // Pose 설정
    setMarkerPose(id, pose);

    // 순서/좌표 기록
    markerOrder_.push_back(id);
    markerPoses_.push_back(pose);

    LOGI("Added marker %d at pose (%f,%f,%f)",
         id, pose.x(), pose.y(), pose.z());
}

void Scene::setMarkerPose(int id, const rtabmap::Transform & pose)
{
    UASSERT(!pose.isNull());
    std::map<int, tango_gl::Axis*>::iterator iter=markers_.find(id);
    if(iter != markers_.end())
    {
        glm::vec3 position(pose.x(), pose.y(), pose.z());
        Eigen::Quaternionf quat = pose.getQuaternionf();
        glm::quat rotation(quat.w(), quat.x(), quat.y(), quat.z());
        iter->second->SetPosition(position);
        iter->second->SetRotation(rotation);
    }
}
bool Scene::hasMarker(int id) const
{
    return markers_.find(id) != markers_.end();
}
void Scene::removeMarker(int id)
{
    std::map<int, tango_gl::Axis*>::iterator iter=markers_.find(id);
    if(iter != markers_.end())
    {
        delete iter->second;
        markers_.erase(iter);
    }
}

void Scene::removeMarkerAll()
{
    LOGI("Removing all markers...");

    // [추가] 먼저, 필터링된 메쉬를 '원본'으로 복원
    for(auto & kv : originalMeshes_)
    {
        int id = kv.first;
        // Scene 내부에 해당 메쉬가 존재한다면
        auto iter = pointClouds_.find(id);
        if(iter != pointClouds_.end() && iter->second->hasMesh())
        {
//            setWireframe(true);
            // 원본 메쉬로 업데이트
            iter->second->updateMesh(kv.second, true);
        }
    }

    // 마커들 삭제 (기존 로직)
    while (!markers_.empty())
    {
        std::map<int, tango_gl::Axis*>::iterator iter = markers_.begin();
        delete iter->second;
        markers_.erase(iter);
    }
    markerOrder_.clear();
    markerPoses_.clear();

    // 폴리곤도 닫힘 상태 해제
    polygonClosed_ = false;
    Render();
}

std::set<int> Scene::getAddedMarkers() const
{
    return uKeysSet(markers_);
}

void Scene::addCloud(
        int id,
        const pcl::PointCloud<pcl::PointXYZRGB>::Ptr & cloud,
        const pcl::IndicesPtr & indices,
        const rtabmap::Transform & pose)
{
    LOGI("add cloud %d (%d points %d indices)", id, (int)cloud->size(), indices.get()?(int)indices->size():0);
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        delete iter->second;
        pointClouds_.erase(iter);
    }

    //create
    PointCloudDrawable * drawable = new PointCloudDrawable(cloud, indices);
    drawable->setPose(pose);
    pointClouds_.insert(std::make_pair(id, drawable));
}

void Scene::addMesh(
        int id,
        const rtabmap::Mesh & mesh,
        const rtabmap::Transform & pose,
        bool createWireframe)
{
    LOGI("add mesh %d", id);
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        delete iter->second;
        pointClouds_.erase(iter);
    }
    //기존 메쉬 보관
    originalMeshes_[id] = mesh;

    PointCloudDrawable * drawable = new PointCloudDrawable(mesh, createWireframe);
    drawable->setPose(pose);
    pointClouds_.insert(std::make_pair(id, drawable));

    if(!mesh.pose.isNull() && mesh.cloud->size() && (!mesh.cloud->isOrganized() || mesh.indices->size()))
    {
        UTimer time;
        float height = 0.0f;
        Eigen::Affine3f affinePose = mesh.pose.toEigen3f();
        if(mesh.polygons.size())
        {
            for(unsigned int i=0; i<mesh.polygons.size(); ++i)
            {
                for(unsigned int j=0; j<mesh.polygons[i].vertices.size(); ++j)
                {
                    pcl::PointXYZRGB pt = pcl::transformPoint(mesh.cloud->at(mesh.polygons[i].vertices[j]), affinePose);
                    if(pt.z < height)
                    {
                        height = pt.z;
                    }
                }
            }
        }
        else
        {
            if(mesh.cloud->isOrganized())
            {
                for(unsigned int i=0; i<mesh.indices->size(); ++i)
                {
                    pcl::PointXYZRGB pt = pcl::transformPoint(mesh.cloud->at(mesh.indices->at(i)), affinePose);
                    if(pt.z < height)
                    {
                        height = pt.z;
                    }
                }
            }
            else
            {
                for(unsigned int i=0; i<mesh.cloud->size(); ++i)
                {
                    pcl::PointXYZRGB pt = pcl::transformPoint(mesh.cloud->at(i), affinePose);
                    if(pt.z < height)
                    {
                        height = pt.z;
                    }
                }
            }
        }

        if(grid_->GetPosition().y == kHeightOffset.y || grid_->GetPosition().y > height)
        {
            grid_->SetPosition(glm::vec3(0,height,0));
        }
        LOGD("compute min height %f s", time.ticks());
    }
}

void Scene::setCloudPose(int id, const rtabmap::Transform & pose)
{
    UASSERT(!pose.isNull());
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        iter->second->setPose(pose);
    }
}

void Scene::setCloudVisible(int id, bool visible)
{
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        iter->second->setVisible(visible);
    }
}

bool Scene::hasCloud(int id) const
{
    return pointClouds_.find(id) != pointClouds_.end();
}

bool Scene::hasMesh(int id) const
{
    return pointClouds_.find(id) != pointClouds_.end() && pointClouds_.at(id)->hasMesh();
}

bool Scene::hasTexture(int id) const
{
    return pointClouds_.find(id) != pointClouds_.end() && pointClouds_.at(id)->hasTexture();
}

std::set<int> Scene::getAddedClouds() const
{
    return uKeysSet(pointClouds_);
}

void Scene::updateCloudPolygons(int id, const std::vector<pcl::Vertices> & polygons)
{
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        iter->second->updatePolygons(polygons);
    }
}

void Scene::updateMesh(int id, const rtabmap::Mesh & mesh)
{
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        originalMeshes_[id] = mesh;
        
        iter->second->updateMesh(mesh);
    }
}

void Scene::updateGains(int id, float gainR, float gainG, float gainB)
{
    std::map<int, PointCloudDrawable*>::iterator iter=pointClouds_.find(id);
    if(iter != pointClouds_.end())
    {
        iter->second->setGains(gainR, gainG, gainB);
    }
}

void Scene::setGridColor(float r, float g, float b)
{
    if(grid_)
    {
        grid_->SetColor(r, g, b);
    }
}

void Scene::filterMeshInsidePolygon(
    const std::vector<rtabmap::Transform> & polygon2D,
    rtabmap::Mesh & mesh,
    const rtabmap::Transform & drawablePose /* 추가 인자 */ )
{
    if(polygon2D.size() < 3 || mesh.cloud->empty())
    {
        LOGW("filterMeshInsidePolygon: polygon or mesh invalid.");
        return;
    }

    // (1) 2D 폴리곤 (씬 좌표계)
    std::vector<cv::Point2f> polyPoints;
    polyPoints.reserve(polygon2D.size());
    for(const auto & t : polygon2D)
    {
        polyPoints.push_back(cv::Point2f(t.x(), t.z()));
    }

    // (2) 메쉬 로컬 → 씬 좌표
    //     - Drawable Pose * mesh.pose
    rtabmap::Transform meshToScene = rtabmap::Transform::getIdentity();
    if(!drawablePose.isNull() && !mesh.pose.isNull())
    {
        meshToScene = drawablePose * mesh.pose;
    }
    else if(!mesh.pose.isNull())
    {
        // fallback: mesh.pose만 사용
        meshToScene = mesh.pose;
    }
    Eigen::Affine3f meshToSceneEigen = meshToScene.toEigen3f();

    // (3) 폴리곤 내부 판별
    std::vector<pcl::Vertices> newPolygons;
    newPolygons.reserve(mesh.polygons.size());

    for(const auto & poly : mesh.polygons)
    {
        bool allInside = true;
        for(unsigned int i=0; i<poly.vertices.size(); ++i)
        {
            int idx = poly.vertices[i];
            if(idx < 0 || idx >= int(mesh.cloud->size()))
            {
                allInside = false;
                break;
            }
            // 로컬 점
            const pcl::PointXYZRGB & ptLocal = mesh.cloud->at(idx);
            // 씬 좌표로
            pcl::PointXYZRGB ptScene =
                pcl::transformPoint(ptLocal, meshToSceneEigen);
            // 2D만 사용
            cv::Point2f pt2D(ptScene.x, ptScene.z);
            // OpenCV 폴리곤 내부 여부
            double inside = cv::pointPolygonTest(polyPoints, pt2D, false);
            if(inside < 0)
            {
                allInside = false;
                break;
            }
        }
        if(allInside)
        {
            newPolygons.push_back(poly);
        }
    }

    LOGI("filterMeshInsidePolygon() -> original polygons=%d, filtered=%d",
         int(mesh.polygons.size()),
         int(newPolygons.size()));

    // (4) 결과 반영
    mesh.polygons = newPolygons;
}

/**
 * @brief Scene::calculateMeshVolumeByPolygon
 *  crop에 사용된 폴리곤(마커)들의 3D 중심점을 기준으로,
 *  해당 meshId의 메쉬 (이미 crop된 상태)를 대상으로 부피를 계산한다.
 *
 *  - (A) 폴리곤(마커) 중심점 = 모든 마커 x,y,z 평균
 *  - (B) 위 점을 기준점 c로 하여, 삼각형 테트라볼륨을 누적 계산
 *
 * @param meshId : pointClouds_에 등록된 메쉬 ID
 * @return 계산된 부피 (양수)
 */
double Scene::calculateMeshVolume(int meshId)
{
    totalVolume = 0.0;
    // (1) pointClouds_에서 대상 메쉬 찾기
    auto iter = pointClouds_.find(meshId);
    if(iter == pointClouds_.end())
    {
        UERROR("calculateMeshVolumeByPolygon() -> Cannot find mesh with id=%d", meshId);
        return 0.0;
    }
    PointCloudDrawable * drawable = iter->second;
    if(!drawable->hasMesh())
    {
        UERROR("calculateMeshVolumeByPolygon() -> This drawable (id=%d) has no mesh!", meshId);
        return 0.0;
    }

    // (2) crop된(업데이트된) 메쉬 가져오기
    rtabmap::Mesh mesh = drawable->getMesh();
    if(mesh.polygons.empty())
    {
        UWARN("calculateMeshVolumeByPolygon() -> mesh has no polygons (id=%d).", meshId);
        return 0.0;
    }

    // (3) Scene 좌표계로 변환
    //     - drawable 자체 pose * mesh.pose
    rtabmap::Transform meshToScene = rtabmap::Transform::getIdentity();
    if(!drawable->getPose().isNull() && !mesh.pose.isNull())
    {
        meshToScene = drawable->getPose() * mesh.pose;
    }
    else if(!mesh.pose.isNull())
    {
        meshToScene = mesh.pose;
    }
    Eigen::Affine3f meshToSceneEigen = meshToScene.toEigen3f();

    // (4) 메쉬 정점을 Scene 좌표로 변환
    std::vector<pcl::PointXYZ> sceneVertices;
    sceneVertices.reserve(mesh.cloud->size());

    for(size_t i=0; i<mesh.cloud->size(); ++i)
    {
        const pcl::PointXYZRGB & ptLocal = mesh.cloud->at(i);

        // PointXYZRGB로 먼저 변환
        pcl::PointXYZRGB ptColored = pcl::transformPoint(ptLocal, meshToSceneEigen);

        // x,y,z만 사용
        pcl::PointXYZ ptScene;
        ptScene.x = ptColored.x;
        ptScene.y = ptColored.y;
        ptScene.z = ptColored.z;
        
        sceneVertices.push_back(ptScene);
    }

    // (5) 폴리곤(마커) 중심점(Scene 좌표계) 구하기
    pcl::PointXYZ polyCentroid = computeMarkerPolygonCentroid();

    // (6) 모든 삼각형에 대해, polyCentroid를 기준점 c로 하는 테트라볼륨 누적
    for(const auto & polygon : mesh.polygons)
    {
        if(polygon.vertices.size() < 3) continue;

        for(size_t i=1; i+1<polygon.vertices.size(); ++i)
        {
            int i0 = polygon.vertices[0];
            int i1 = polygon.vertices[i];
            int i2 = polygon.vertices[i+1];
            if( i0<0 || i1<0 || i2<0 ||
                i0>=int(sceneVertices.size()) ||
                i1>=int(sceneVertices.size()) ||
                i2>=int(sceneVertices.size()) )
            {
                continue;
            }

            const pcl::PointXYZ & v0 = sceneVertices[i0];
            const pcl::PointXYZ & v1 = sceneVertices[i1];
            const pcl::PointXYZ & v2 = sceneVertices[i2];

            Eigen::Vector3f vec0(v0.x - polyCentroid.x,
                                 v0.y - polyCentroid.y,
                                 v0.z - polyCentroid.z);
            Eigen::Vector3f vec1(v1.x - polyCentroid.x,
                                 v1.y - polyCentroid.y,
                                 v1.z - polyCentroid.z);
            Eigen::Vector3f vec2(v2.x - polyCentroid.x,
                                 v2.y - polyCentroid.y,
                                 v2.z - polyCentroid.z);

            Eigen::Vector3f crossVal = vec0.cross(vec1);
            double signedVolume = crossVal.dot(vec2) / 6.0;
            totalVolume += std::fabs(signedVolume);
        }
    }
    return totalVolume;
}

/**
 * @brief Scene::computeMarkerPolygonCentroid
 *  crop에 사용된 폴리곤(마커들)의 x,y,z 평균점을 구한다.
 *  - polygonClosed_ 등이 true/false이든, markerPoses_만 있으면 계산 가능
 * @return centroid (pcl::PointXYZ). 마커가 없으면 (0,0,0)
 */
pcl::PointXYZ Scene::computeMarkerPolygonCentroid() const
{
    pcl::PointXYZ centroid(0.0f, 0.0f, 0.0f);
    if(markerPoses_.empty())
    {
        return centroid;
    }

    for(const auto & pose : markerPoses_)
    {
        centroid.x += pose.x();
        centroid.y += pose.y();
        centroid.z += pose.z();
    }
    centroid.x /= float(markerPoses_.size());
    centroid.y /= float(markerPoses_.size());
    centroid.z /= float(markerPoses_.size());

    return centroid;
}

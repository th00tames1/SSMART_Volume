#import "RTABMapAppObjC.h"
#include "RTABMapApp.h"

@implementation RTABMapAppObjC

+ (double)calculateMeshVolume
{
    return RTABMapApp::getInstance()->calculateMeshVolume();
}

@end

// `AppCenterApplication.h` used to sit here and start with `@import Cocoa;`, which is what put
// Cocoa (and with it CoreGraphics / ApplicationServices) in scope for the Swift files that carry
// no import of their own — the api-wrappers around SkyLight and HIServices. AppCenter is gone;
// the import it happened to provide is not optional, so it is stated here directly.
@import Cocoa;

#import "ObjCExceptionCatcher.h"

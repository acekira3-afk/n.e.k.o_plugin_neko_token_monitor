#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <signal.h>
static volatile sig_atomic_t stopping=0;
static void stopWidget(int signalNumber){stopping=1;}

@interface InputPanel : NSPanel
@end
@implementation InputPanel
- (BOOL)canBecomeKeyWindow{return YES;}
@end

@interface WidgetDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property NSPanel *panel;
@property WKWebView *web;
@property NSPoint dragMouse;
@property NSPoint dragOrigin;
@property BOOL dragging;
@property NSString *base;
@property pid_t parent;
@property NSMutableDictionary<NSNumber *, NSRunningApplication *> *hiddenApps;
@property NSMutableDictionary<NSNumber *, NSRunningApplication *> *minimizedApps;
@property BOOL recording;
@property NSMutableDictionary<NSNumber *, NSRunningApplication *> *pausedApps;
@property NSMutableSet<NSNumber *> *confirmedPausedApps;
@property BOOL accessibilityPrompted;
@property NSInteger hideAttempts;
@property NSMutableSet<NSNumber *> *accessibilityHiddenApps;
@property BOOL movedPointer;
@property CGPoint savedPointer;
@property CGPoint lastHoverPoint;
@end
@implementation WidgetDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.base=@"http://127.0.0.1:48923";
    self.parent=getppid();
    self.hiddenApps=[NSMutableDictionary new];
    self.minimizedApps=[NSMutableDictionary new];
    self.pausedApps=[NSMutableDictionary new];
    self.confirmedPausedApps=[NSMutableSet new];
    self.accessibilityHiddenApps=[NSMutableSet new];
    signal(SIGTERM,stopWidget);
    self.panel=[[InputPanel alloc] initWithContentRect:NSMakeRect(0,0,400,404) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.title=@"猫粮";
    self.panel.opaque=NO;self.panel.backgroundColor=NSColor.clearColor;self.panel.hasShadow=NO;
    self.panel.level=NSFloatingWindowLevel;self.panel.hidesOnDeactivate=NO;
    self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSRect screen=NSScreen.mainScreen.visibleFrame;
    [self.panel setFrameOrigin:NSMakePoint(NSMaxX(screen)-420,NSMinY(screen)+20)];
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:self name:@"nekoWidget"];
    self.web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,0,400,404) configuration:config];
    [self.web setValue:@NO forKey:@"drawsBackground"];
    self.web.navigationDelegate=self;
    self.panel.contentView=self.web;
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[self.base stringByAppendingString:@"/widget"]]]];
    [self.panel orderFrontRegardless];
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){if(stopping||getppid()!=self.parent||kill(self.parent,0)!=0)[NSApp terminate:nil];else if(self.recording)[self hideOriginal];}];
}
- (BOOL)isNeko:(NSRunningApplication *)app {
    if(app.processIdentifier==getpid())return NO;
    NSString *name=[[app.localizedName lowercaseString] stringByReplacingOccurrencesOfString:@"." withString:@""];
    return [app.bundleIdentifier isEqualToString:@"cn.nekotech.neko"]||[name isEqualToString:@"neko"]||[name isEqualToString:@"neko desktop"];
}
- (BOOL)setAccessibilityHidden:(BOOL)hidden app:(NSRunningApplication *)app {
    // Never prompt or grant permissions here; the user must explicitly enable access in macOS.
    if(!AXIsProcessTrusted())return NO;
    AXUIElementRef target=AXUIElementCreateApplication(app.processIdentifier);
    Boolean settable=false;
    AXError check=AXUIElementIsAttributeSettable(target,kAXHiddenAttribute,&settable);
    AXError result=(check==kAXErrorSuccess&&settable)?AXUIElementSetAttributeValue(target,kAXHiddenAttribute,hidden?kCFBooleanTrue:kCFBooleanFalse):kAXErrorAttributeUnsupported;
    CFTypeRef actual=NULL;
    BOOL confirmed=result==kAXErrorSuccess&&AXUIElementCopyAttributeValue(target,kAXHiddenAttribute,&actual)==kAXErrorSuccess&&CFGetTypeID(actual)==CFBooleanGetTypeID()&&CFBooleanGetValue(actual)==hidden;
    if(hidden&&result==kAXErrorSuccess)[self.accessibilityHiddenApps addObject:@(app.processIdentifier)];
    NSLog(@"CatFood AX hidden=%d settable=%d check=%d result=%d confirmed=%d",hidden,settable,check,result,confirmed);
    if(actual)CFRelease(actual);CFRelease(target);
    return confirmed;
}
// Use NEKO's own goodbye/return controls so its renderer snapshots geometry and pauses.
- (AXUIElementRef)findControl:(NSString *)label root:(AXUIElementRef)root depth:(NSUInteger)depth {
    if(depth>24)return NULL;
    for(NSString *attribute in @[(__bridge NSString *)kAXDescriptionAttribute,(__bridge NSString *)kAXTitleAttribute,(__bridge NSString *)kAXHelpAttribute]){
        CFTypeRef value=NULL;
        if(AXUIElementCopyAttributeValue(root,(__bridge CFStringRef)attribute,&value)==kAXErrorSuccess&&value){
            BOOL matches=CFGetTypeID(value)==CFStringGetTypeID()&&[(__bridge NSString *)value isEqualToString:label];
            CFRelease(value);if(matches)return (AXUIElementRef)CFRetain(root);
        }
    }
    CFTypeRef children=NULL;
    if(AXUIElementCopyAttributeValue(root,kAXChildrenAttribute,&children)!=kAXErrorSuccess||!children)return NULL;
    AXUIElementRef found=NULL;
    if(CFGetTypeID(children)==CFArrayGetTypeID())for(id child in (__bridge NSArray *)children){
        found=[self findControl:label root:(__bridge AXUIElementRef)child depth:depth+1];if(found)break;
    }
    CFRelease(children);return found;
}
- (AXUIElementRef)mainHostWindow:(AXUIElementRef)root {
    CFTypeRef windows=NULL;
    if(AXUIElementCopyAttributeValue(root,kAXWindowsAttribute,&windows)!=kAXErrorSuccess||!windows)return (AXUIElementRef)CFRetain(root);
    AXUIElementRef chosen=NULL;
    if(CFGetTypeID(windows)==CFArrayGetTypeID())for(id candidate in (__bridge NSArray *)windows){
        CFTypeRef title=NULL;
        AXUIElementCopyAttributeValue((__bridge AXUIElementRef)candidate,kAXTitleAttribute,&title);
        BOOL main=title&&CFGetTypeID(title)==CFStringGetTypeID()&&[(__bridge NSString *)title isEqualToString:@"Project N.E.K.O."];
        if(title)CFRelease(title);
        if(main){chosen=(AXUIElementRef)CFRetain((__bridge AXUIElementRef)candidate);break;}
    }
    CFRelease(windows);
    return chosen?:((AXUIElementRef)CFRetain(root));
}
- (BOOL)setHostWindowMinimized:(BOOL)minimized app:(NSRunningApplication *)app {
    AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementRef host=[self mainHostWindow:root];
    Boolean settable=false;
    AXError check=AXUIElementIsAttributeSettable(host,kAXMinimizedAttribute,&settable);
    AXError result=(check==kAXErrorSuccess&&settable)?AXUIElementSetAttributeValue(host,kAXMinimizedAttribute,minimized?kCFBooleanTrue:kCFBooleanFalse):kAXErrorAttributeUnsupported;
    CFTypeRef actual=NULL;
    BOOL confirmed=result==kAXErrorSuccess&&AXUIElementCopyAttributeValue(host,kAXMinimizedAttribute,&actual)==kAXErrorSuccess&&actual&&CFGetTypeID(actual)==CFBooleanGetTypeID()&&CFBooleanGetValue(actual)==minimized;
    NSLog(@"CatFood window minimized=%d settable=%d check=%d result=%d confirmed=%d",minimized,settable,check,result,confirmed);
    if(actual)CFRelease(actual);CFRelease(host);CFRelease(root);
    return confirmed;
}
- (BOOL)isHostHidden:(NSRunningApplication *)app {
    if(app.hidden)return YES;
    AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier);
    CFTypeRef hidden=NULL;
    BOOL result=AXUIElementCopyAttributeValue(root,kAXHiddenAttribute,&hidden)==kAXErrorSuccess&&hidden&&CFGetTypeID(hidden)==CFBooleanGetTypeID()&&CFBooleanGetValue(hidden);
    if(hidden)CFRelease(hidden);
    if(!result){
        AXUIElementRef window=[self mainHostWindow:root];
        CFTypeRef minimized=NULL;
        result=AXUIElementCopyAttributeValue(window,kAXMinimizedAttribute,&minimized)==kAXErrorSuccess&&minimized&&CFGetTypeID(minimized)==CFBooleanGetTypeID()&&CFBooleanGetValue(minimized);
        if(minimized)CFRelease(minimized);CFRelease(window);
    }
    CFRelease(root);return result;
}
- (void)restorePointer {
    self.panel.ignoresMouseEvents=NO;
    if(!self.movedPointer)return;
    CGEventRef current=CGEventCreate(NULL);
    CGPoint point=current?CGEventGetLocation(current):CGPointZero;
    if(current)CFRelease(current);
    if(hypot(point.x-self.lastHoverPoint.x,point.y-self.lastHoverPoint.y)<24){
        CGEventRef move=CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,self.savedPointer,kCGMouseButtonLeft);
        if(move){CGEventPost(kCGHIDEventTap,move);CFRelease(move);}
    }
    self.movedPointer=NO;
}
- (BOOL)revealHostControls:(AXUIElementRef)element app:(NSRunningApplication *)app depth:(NSUInteger)depth {
    if(depth>24)return NO;
    CFTypeRef role=NULL,position=NULL,size=NULL;
    AXUIElementCopyAttributeValue(element,kAXRoleAttribute,&role);
    BOOL image=role&&CFGetTypeID(role)==CFStringGetTypeID()&&CFEqual(role,kAXImageRole);
    if(role)CFRelease(role);
    if(image){
        AXUIElementCopyAttributeValue(element,kAXPositionAttribute,&position);
        AXUIElementCopyAttributeValue(element,kAXSizeAttribute,&size);
        CGPoint p;CGSize z;
        BOOL valid=position&&size&&CFGetTypeID(position)==AXValueGetTypeID()&&CFGetTypeID(size)==AXValueGetTypeID()
            &&AXValueGetValue(position,kAXValueCGPointType,&p)&&AXValueGetValue(size,kAXValueCGSizeType,&z)&&z.width>80&&z.height>100;
        if(position)CFRelease(position);if(size)CFRelease(size);
        if(valid){
            // The toolbar follows the real cursor. Delivering a synthetic move only to
            // Electron's process does not reveal it; briefly pass mouse events through
            // our panel and restore the user's cursor after the takeover attempt.
            if(!self.movedPointer){
                CGEventRef current=CGEventCreate(NULL);
                if(current){self.savedPointer=CGEventGetLocation(current);CFRelease(current);self.movedPointer=YES;}
            }
            self.panel.ignoresMouseEvents=YES;
            [app activateWithOptions:0];
            // NEKO's AX image is the full-screen canvas, while YUI stands at its
            // right edge. Hover the character area rather than the canvas center.
            CGPoint target=CGPointMake(p.x+z.width*0.89,p.y+z.height*0.30);
            for(CGFloat shift=-180;shift<=0;shift+=180){
                CGPoint at=CGPointMake(target.x+shift,target.y);
                CGEventRef event=CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,at,kCGMouseButtonLeft);
                if(event){CGEventPost(kCGHIDEventTap,event);CFRelease(event);}
            }
            self.lastHoverPoint=target;
            NSLog(@"CatFood requested visible host hover pid=%d canvas=(%.0f,%.0f %.0fx%.0f) at=(%.0f,%.0f)",app.processIdentifier,p.x,p.y,z.width,z.height,target.x,target.y);return YES;
        }
    }
    CFTypeRef children=NULL;
    if(AXUIElementCopyAttributeValue(element,kAXChildrenAttribute,&children)!=kAXErrorSuccess||!children)return NO;
    BOOL result=NO;
    if(CFGetTypeID(children)==CFArrayGetTypeID())for(id child in (__bridge NSArray *)children){
        if([self revealHostControls:(__bridge AXUIElementRef)child app:app depth:depth+1]){result=YES;break;}
    }
    CFRelease(children);return result;
}
- (BOOL)hostControl:(NSString *)label app:(NSRunningApplication *)app press:(BOOL)press {
    if(!AXIsProcessTrusted()||![self isNeko:app]||app.terminated)return NO;
    AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementSetMessagingTimeout(root,0.5);
    AXUIElementRef host=[self mainHostWindow:root];
    AXUIElementRef control=[self findControl:label root:host depth:0];
    BOOL result=control!=NULL;
    if(!control){AXUIElementPerformAction(host,kAXRaiseAction);[self revealHostControls:host app:app depth:0];}
    if(control&&press){
        AXError status=AXUIElementPerformAction(control,kAXPressAction);
        if(status!=kAXErrorSuccess){
            CFTypeRef parent=NULL;
            if(AXUIElementCopyAttributeValue(control,kAXParentAttribute,&parent)==kAXErrorSuccess&&parent){
                status=AXUIElementPerformAction((AXUIElementRef)parent,kAXPressAction);CFRelease(parent);
            }
        }
        NSLog(@"CatFood host control %@ status=%d",label,status);result=status==kAXErrorSuccess;
    }
    if(control)CFRelease(control);CFRelease(host);CFRelease(root);return result;
}
- (BOOL)pauseOriginal:(NSRunningApplication *)app {
    NSNumber *pid=@(app.processIdentifier);
    if([self hostControl:@"请她回来" app:app press:NO])return YES;
    if(self.pausedApps[pid])return NO; // Wait for the host transition; never press twice.
    if([self hostControl:@"请她离开" app:app press:YES]){
        self.pausedApps[pid]=app;
        return [self hostControl:@"请她回来" app:app press:NO];
    }
    return NO;
}
- (void)hideOriginal {
    NSUInteger found=0;BOOL ok=YES;
    for(NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications){
        if(![self isNeko:app]||app.terminated)continue;
        found++;
        NSNumber *pid=@(app.processIdentifier);
        if(self.hiddenApps[pid]&&[self.confirmedPausedApps containsObject:pid]&&[self isHostHidden:app])continue;
        if(![self pauseOriginal:app]){ok=NO;continue;}
        [self.confirmedPausedApps addObject:pid];
        if(!app.hidden){
            self.hiddenApps[@(app.processIdentifier)]=app;
            BOOL accepted=[app hide];
            NSLog(@"CatFood hide pid=%d accepted=%d hidden=%d",app.processIdentifier,accepted,app.hidden);
            accepted=accepted&&app.hidden;
            if(!accepted){
                if(!AXIsProcessTrusted()&&!self.accessibilityPrompted){
                    self.accessibilityPrompted=YES;
                    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
                }
                accepted=[self setAccessibilityHidden:YES app:app];
                if(accepted)[self.accessibilityHiddenApps addObject:@(app.processIdentifier)];
                else if([self setHostWindowMinimized:YES app:app])self.minimizedApps[pid]=app;
                else ok=NO;
            }
        }
    }
    if((!ok||found==0)&&self.recording&&self.hideAttempts++<18){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.recording)[self hideOriginal];});
        return;
    }
    if(ok)self.hideAttempts=0;
    [self restorePointer];
    NSLog(@"CatFood takeover result targets=%lu ok=%d attempts=%ld",(unsigned long)found,found>0&&ok,(long)self.hideAttempts);
    NSString *js=[NSString stringWithFormat:@"window.catfoodNativeState && window.catfoodNativeState({active:true,ok:%@,paused:true,targets:%lu})",(found>0&&ok)?@"true":@"false",(unsigned long)found];
    [self.web evaluateJavaScript:js completionHandler:nil];
}
- (void)restoreOriginal {
    self.recording=NO;
    [self restorePointer];
    for(NSRunningApplication *app in self.hiddenApps.allValues)if(!app.terminated){
        if([self.accessibilityHiddenApps containsObject:@(app.processIdentifier)])[self setAccessibilityHidden:NO app:app];
        else [app unhide];
        if(self.minimizedApps[@(app.processIdentifier)])[self setHostWindowMinimized:NO app:app];
    }
    [self.minimizedApps removeAllObjects];
    [self.accessibilityHiddenApps removeAllObjects];
    [self.hiddenApps removeAllObjects];
    for(NSRunningApplication *app in self.pausedApps.allValues){
        if(app.terminated)continue;
        for(NSInteger attempt=0;attempt<6;attempt++){
            if([self hostControl:@"请她回来" app:app press:YES])break;
            [NSThread sleepForTimeInterval:0.12];
        }
    }
    [self.pausedApps removeAllObjects];
    [self.confirmedPausedApps removeAllObjects];
}
- (void)applicationWillTerminate:(NSNotification *)notification {[self restoreOriginal];}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if(!message.frameInfo.isMainFrame||![message.frameInfo.securityOrigin.host isEqualToString:@"127.0.0.1"]||message.frameInfo.securityOrigin.port!=48923)return;
    if(![message.body isKindOfClass:NSString.class])return;
    NSString *action=message.body;
    if([action isEqualToString:@"settings"])[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:self.base]];
    else if([action isEqualToString:@"recordStart"]){
        // Status polling and initial page load can both request the same session.
        // Retrying a completed takeover would activate and unhide NEKO again.
        if(self.recording)return;
        if(!AXIsProcessTrusted()){
            if(!self.accessibilityPrompted){
                self.accessibilityPrompted=YES;
                AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
            }
            NSLog(@"CatFood cannot take over: Accessibility permission is unavailable");
            [self.web evaluateJavaScript:@"window.catfoodNativeState && window.catfoodNativeState({active:true,ok:false,reason:'accessibility'})" completionHandler:nil];
        }else{self.recording=YES;self.hideAttempts=0;[self hideOriginal];}
    }
    else if([action isEqualToString:@"recordEnd"])[self restoreOriginal];
    else if([action isEqualToString:@"hide"])[NSApp terminate:nil];
    else if([action isEqualToString:@"dragStart"]){self.dragging=YES;self.dragMouse=NSEvent.mouseLocation;self.dragOrigin=self.panel.frame.origin;}
    else if([action isEqualToString:@"dragEnd"])self.dragging=NO;
    else if([action isEqualToString:@"dragMove"]&&self.dragging){NSPoint p=NSEvent.mouseLocation;[self.panel setFrameOrigin:NSMakePoint(self.dragOrigin.x+p.x-self.dragMouse.x,self.dragOrigin.y+p.y-self.dragMouse.y)];}
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *url=action.request.URL;
    handler(([url.host isEqualToString:@"127.0.0.1"]&&url.port.integerValue==48923&&[url.scheme isEqualToString:@"http"])?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
@end
int main(int argc,const char *argv[]){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];WidgetDelegate *delegate=[WidgetDelegate new];app.delegate=delegate;[app run];}return 0;}

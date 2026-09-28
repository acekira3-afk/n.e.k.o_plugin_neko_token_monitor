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
@property BOOL recording;
@property NSMutableDictionary<NSNumber *, NSRunningApplication *> *pausedApps;
@property BOOL accessibilityPrompted;
@property NSInteger hideAttempts;
@property NSMutableSet<NSNumber *> *accessibilityHiddenApps;
@end
@implementation WidgetDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.base=@"http://127.0.0.1:48923";
    self.parent=getppid();
    self.hiddenApps=[NSMutableDictionary new];
    self.pausedApps=[NSMutableDictionary new];
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
            // Targeted hover only: expose NEKO's controls without clicking or moving the user's pointer.
            CGEventRef event=CGEventCreateMouseEvent(NULL,kCGEventMouseMoved,CGPointMake(p.x+z.width/2,p.y+z.height/2),kCGMouseButtonLeft);
            CGEventPostToPid(app.processIdentifier,event);CFRelease(event);
            NSLog(@"CatFood requested host controls hover pid=%d",app.processIdentifier);return YES;
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
    AXUIElementRef control=[self findControl:label root:root depth:0];
    BOOL result=control!=NULL;
    if(!control&&press&&[label isEqualToString:@"请她离开"])[self revealHostControls:root app:app depth:0];
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
    if(control)CFRelease(control);CFRelease(root);return result;
}
- (BOOL)pauseOriginal:(NSRunningApplication *)app {
    NSNumber *pid=@(app.processIdentifier);
    if([self hostControl:@"请她回来" app:app press:NO])return YES;
    if(self.pausedApps[pid])return NO; // transition still running; never toggle twice
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
        if(![self pauseOriginal:app]){ok=NO;continue;}
        if(!app.hidden){
            self.hiddenApps[@(app.processIdentifier)]=app;
            BOOL accepted=[app hide];
            NSLog(@"CatFood hide pid=%d accepted=%d hidden=%d",app.processIdentifier,accepted,app.hidden);
            if(!accepted){
                if(!AXIsProcessTrusted()&&!self.accessibilityPrompted){
                    self.accessibilityPrompted=YES;
                    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
                }
                accepted=[self setAccessibilityHidden:YES app:app];
                if(accepted)[self.accessibilityHiddenApps addObject:@(app.processIdentifier)];
                else ok=NO;
            }
        }
    }
    if(!ok&&self.recording&&self.hideAttempts++<5){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.recording)[self hideOriginal];});
        return;
    }
    if(ok)self.hideAttempts=0;
    NSString *js=[NSString stringWithFormat:@"window.catfoodNativeState && window.catfoodNativeState({active:true,ok:%@,paused:true,targets:%lu})",(found>0&&ok)?@"true":@"false",(unsigned long)found];
    [self.web evaluateJavaScript:js completionHandler:nil];
}
- (void)restoreOriginal {
    self.recording=NO;
    for(NSRunningApplication *app in self.hiddenApps.allValues)if(!app.terminated){
        if([self.accessibilityHiddenApps containsObject:@(app.processIdentifier)])[self setAccessibilityHidden:NO app:app];
        else [app unhide];
    }
    [self.accessibilityHiddenApps removeAllObjects];
    [self.hiddenApps removeAllObjects];
    for(NSRunningApplication *app in self.pausedApps.allValues){
        if(!app.terminated)[self hostControl:@"请她回来" app:app press:YES];
    }
    [self.pausedApps removeAllObjects];
}
- (void)applicationWillTerminate:(NSNotification *)notification {[self restoreOriginal];}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if(!message.frameInfo.isMainFrame||![message.frameInfo.securityOrigin.host isEqualToString:@"127.0.0.1"]||message.frameInfo.securityOrigin.port!=48923)return;
    if(![message.body isKindOfClass:NSString.class])return;
    NSString *action=message.body;
    if([action isEqualToString:@"settings"])[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:self.base]];
    else if([action isEqualToString:@"recordStart"]){self.recording=YES;self.hideAttempts=0;[self hideOriginal];}
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

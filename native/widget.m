#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
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
@end
@implementation WidgetDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.base=@"http://127.0.0.1:48923";
    self.parent=getppid();
    self.hiddenApps=[NSMutableDictionary new];
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
- (void)hideOriginal {
    NSUInteger found=0;BOOL ok=YES;
    for(NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications){
        if(![self isNeko:app]||app.terminated)continue;
        found++;
        if(!app.hidden){
            self.hiddenApps[@(app.processIdentifier)]=app;
            if(![app hide])ok=NO;
        }
    }
    NSString *js=[NSString stringWithFormat:@"window.catfoodNativeState && window.catfoodNativeState({active:true,ok:%@,targets:%lu})",(found>0&&ok)?@"true":@"false",(unsigned long)found];
    [self.web evaluateJavaScript:js completionHandler:nil];
}
- (void)restoreOriginal {
    self.recording=NO;
    for(NSRunningApplication *app in self.hiddenApps.allValues)if(!app.terminated)[app unhide];
    [self.hiddenApps removeAllObjects];
}
- (void)applicationWillTerminate:(NSNotification *)notification {[self restoreOriginal];}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if(!message.frameInfo.isMainFrame||![message.frameInfo.securityOrigin.host isEqualToString:@"127.0.0.1"]||message.frameInfo.securityOrigin.port!=48923)return;
    if(![message.body isKindOfClass:NSString.class])return;
    NSString *action=message.body;
    if([action isEqualToString:@"settings"])[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:self.base]];
    else if([action isEqualToString:@"recordStart"]){self.recording=YES;[self hideOriginal];}
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

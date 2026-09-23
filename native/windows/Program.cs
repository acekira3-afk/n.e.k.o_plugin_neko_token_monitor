using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

class CatFood : Form {
    readonly WebView2 web = new WebView2();
    readonly List<IntPtr> hidden = new List<IntPtr>();
    readonly Timer life = new Timer { Interval=1000 };
    readonly int parent;
    readonly string baseUrl;
    readonly string stopFile;
    readonly bool smoke;
    Point mouse, origin;
    bool dragging;
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
    delegate bool EnumProc(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    public CatFood(string[] args) {
        parent=int.Parse(args[0]);baseUrl=args[1];stopFile=args[2];smoke=Array.IndexOf(args,"--smoke")>=0;
        Text="猫粮";FormBorderStyle=FormBorderStyle.None;ClientSize=new Size(400,404);TopMost=true;
        BackColor=Color.Magenta;TransparencyKey=Color.Magenta;ShowInTaskbar=true;
        StartPosition=FormStartPosition.Manual;var area=Screen.PrimaryScreen.WorkingArea;Location=new Point(area.Right-420,area.Bottom-424);
        web.Dock=DockStyle.Fill;web.DefaultBackgroundColor=Color.Transparent;Controls.Add(web);
        Shown+=async(s,e)=>{try {
            var folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NekoCatFood","WebView2");
            var env=await CoreWebView2Environment.CreateAsync(null,folder);
            await web.EnsureCoreWebView2Async(env);
            web.CoreWebView2.Settings.AreDevToolsEnabled=false;
            web.CoreWebView2.Settings.AreDefaultContextMenusEnabled=false;
            web.CoreWebView2.NewWindowRequested+=(a,b)=>b.Handled=true;
            web.CoreWebView2.NavigationStarting+=(a,b)=>{if(!b.Uri.StartsWith(baseUrl+"/",StringComparison.Ordinal))b.Cancel=true;};
            web.CoreWebView2.WebMessageReceived+=(a,b)=>{if(b.Source.StartsWith(baseUrl+"/",StringComparison.Ordinal))Action(b.TryGetWebMessageAsString());};
            web.CoreWebView2.NavigationCompleted+=(a,b)=>{if(smoke){File.WriteAllText(stopFile+".ready",b.IsSuccess?"ready":"failed");Close();}};
            web.Source=new Uri(baseUrl+"/widget");
        }catch(Exception){MessageBox.Show("猫粮窗口无法启动。请安装 Microsoft Edge WebView2 Runtime 后重试。","猫粮");Close();}};
        life.Tick+=(s,e)=>{try {if(Process.GetProcessById(parent).HasExited||File.Exists(stopFile))Close();}catch {Close();}};life.Start();
        FormClosing+=(s,e)=>{Restore();life.Stop();};
    }
    void Restore(){foreach(var window in hidden)ShowWindow(window,8);hidden.Clear();}
    void Action(string action){
        switch(action){
        case "recordStart":
            EnumWindows((window,data)=>{GetWindowThreadProcessId(window,out uint pid);try{var p=Process.GetProcessById((int)pid);if(p.ProcessName.Equals("N.E.K.O",StringComparison.OrdinalIgnoreCase)&&IsWindowVisible(window)){hidden.Add(window);ShowWindow(window,0);}}catch{}return true;},IntPtr.Zero);break;
        case "recordEnd":Restore();break;
        case "hide":Close();break;
        case "dragStart":mouse=Cursor.Position;origin=Location;dragging=true;break;
        case "dragEnd":dragging=false;break;
        case "dragMove":if(dragging)Location=new Point(origin.X+Cursor.Position.X-mouse.X,origin.Y+Cursor.Position.Y-mouse.Y);break;
        }
    }
    [STAThread] static void Main(string[] args){if(args.Length<3)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new CatFood(args));}
}

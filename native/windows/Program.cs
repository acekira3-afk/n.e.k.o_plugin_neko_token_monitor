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
    readonly Dictionary<IntPtr,uint> hidden = new Dictionary<IntPtr,uint>();
    bool recording;
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
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern bool Process32First(IntPtr snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern bool Process32Next(IntPtr snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] struct ProcessEntry {
        public uint size, usage, pid; public IntPtr heap; public uint module, threads, parent;
        public int priority; public uint flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string exe;
    }
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
        life.Tick+=(s,e)=>{try {if(Process.GetProcessById(parent).HasExited||File.Exists(stopFile))Close();else if(recording)HideOriginal();}catch {Close();}};life.Start();
        FormClosing+=(s,e)=>{Restore();life.Stop();};
    }
    HashSet<uint> HostProcesses(){
        var all=new Dictionary<uint,ProcessEntry>();var hosts=new HashSet<uint>();
        var handle=CreateToolhelp32Snapshot(2,0);
        if(handle==new IntPtr(-1))return hosts;
        try{var entry=new ProcessEntry { size=(uint)Marshal.SizeOf(typeof(ProcessEntry)) };
            if(Process32First(handle,ref entry))do{all[entry.pid]=entry;}while(Process32Next(handle,ref entry));
        }finally{CloseHandle(handle);}
        foreach(var pair in all){var name=Path.GetFileNameWithoutExtension(pair.Value.exe).Replace(".","").Replace("-","").Replace("_","").Replace(" ","").ToLowerInvariant();
            if(name=="neko"||name=="nekodesktop")hosts.Add(pair.Key);
        }
        bool changed;do{changed=false;foreach(var pair in all)if(hosts.Contains(pair.Value.parent)&&hosts.Add(pair.Key))changed=true;}while(changed);
        hosts.Remove((uint)Process.GetCurrentProcess().Id);return hosts;
    }
    async void HideOriginal(){
        var hosts=HostProcesses();bool ok=true;int found=0;
        EnumWindows((window,data)=>{GetWindowThreadProcessId(window,out uint pid);
            if(hosts.Contains(pid)){found++;if(IsWindowVisible(window)){hidden[window]=pid;ShowWindow(window,0);if(IsWindowVisible(window))ok=false;}}
            return true;},IntPtr.Zero);
        try{if(web.CoreWebView2!=null)await web.CoreWebView2.ExecuteScriptAsync("window.catfoodNativeState && window.catfoodNativeState({active:true,ok:"+((found>0&&ok)?"true":"false")+",targets:"+found+"})");}catch{}
    }
    void Restore(){recording=false;foreach(var pair in hidden){if(IsWindow(pair.Key)){GetWindowThreadProcessId(pair.Key,out uint pid);if(pid==pair.Value)ShowWindow(pair.Key,8);}}hidden.Clear();}
    void Action(string action){
        switch(action){
        case "recordStart":recording=true;HideOriginal();break;
        case "recordEnd":Restore();break;
        case "hide":Close();break;
        case "dragStart":mouse=Cursor.Position;origin=Location;dragging=true;break;
        case "dragEnd":dragging=false;break;
        case "dragMove":if(dragging)Location=new Point(origin.X+Cursor.Position.X-mouse.X,origin.Y+Cursor.Position.Y-mouse.Y);break;
        }
    }
    [STAThread] static void Main(string[] args){
        if(args.Length==1&&args[0]=="--fixture"){Application.EnableVisualStyles();var host=new Form {Text="NEKO lifecycle fixture"};host.Shown+=(s,e)=>new Form {Text="NEKO chat fixture"}.Show();Application.Run(host);return;}
        if(args.Length<3)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new CatFood(args));}
}

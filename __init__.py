import asyncio
import os
import subprocess
import sys
from pathlib import Path

from plugin.sdk.plugin import NekoPluginBase, Ok, lifecycle, neko_plugin, plugin_entry

from .agent_status import AgentStatus
from .fleet import Fleet
from .recording import Recording
from .server import start_server


@neko_plugin
class NekoTokenMonitorPlugin(NekoPluginBase):
    def __init__(self, ctx):
        super().__init__(ctx)
        self.monitor = None
        self.server = None
        self.server_thread = None
        self.widget = None
        self.recording = None

    def show_widget(self):
        if sys.platform not in ("darwin", "win32"):
            return {"shown": False, "reason": "桌面挂件支持 macOS 与 Windows", "url": "http://127.0.0.1:48923/widget"}
        if self.widget and self.widget.poll() is None:
            return {"shown": True}
        executable = (
            Path(__file__).parent / "bin" / "NekoBudgetWidget.app" / "Contents" / "MacOS" / "neko-budget-widget"
        )
        arguments = [str(executable)]
        if sys.platform == "win32":
            executable = Path(__file__).parent / "bin" / "windows" / "CatFood.exe"
            self.stop_file = Path(self.data_path("widget.stop"))
            self.stop_file.unlink(missing_ok=True)
            arguments = [str(executable), str(os.getpid()), "http://127.0.0.1:48923", str(self.stop_file)]
        else:
            executable.chmod(executable.stat().st_mode | 0o100)
        self.logger.info("Budget widget: launching native window")
        self.widget = subprocess.Popen(
            arguments, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=False
        )
        self.logger.info("Budget widget: native process launched")
        return {"shown": True, "pid": self.widget.pid}

    def announce(self, text):
        result = self.push_message(
            source="neko_token_monitor",
            visibility=["chat"],
            ai_behavior="blind",
            parts=[{"type": "text", "text": text}],
            priority=5,
        )
        return bool(result.get("submitted"))

    def request_reply(self, line=None):
        try:
            cue = (
                (
                    "用户点击了「猫粮」里的 YUI，希望听你说下面这句台词。请仅回复引号中的台词，不执行任何工具，不增加说明，沿用当前角色语音："
                    + repr(line)
                )
                if line
                else (
                    "用户刚在「猫粮」挂件主动点击了「让原版 YUI 回应」。请沿用当前人设说一句简短、关心但略带傲娇的话，句末带上“喵～”，不要编造余额，不执行工具。"
                )
            )
            result = self.push_message(
                source="neko_token_monitor",
                visibility=[],
                ai_behavior="respond",
                parts=[{"type": "text", "text": cue}],
                priority=5,
            )
            if result.get("submitted"):
                return {"submitted": True, "message": "已交给原软件；回应和出声由 NEKO 当前设置决定。"}
        except Exception:
            pass
        return {"submitted": False, "error": "原软件暂未接收回应请求，请确认 NEKO 已连接对话模型。"}

    @lifecycle(id="startup")
    async def startup(self, **_):
        self.logger.info("Budget widget: startup entered")
        if self.monitor is None:
            monitor = Fleet(self.data_path("balance-monitor"), announce=self.announce)
            self.logger.info("Budget widget: storage ready")
            self.recording = Recording(self.data_path("recording"))
            self.recording.start()
            server, thread = start_server(
                monitor, request_reply=self.request_reply, agent_status=AgentStatus(), recording=self.recording
            )
            self.logger.info("Budget widget: loopback server ready")
            self.monitor, self.server, self.server_thread = monitor, server, thread
            monitor.start()
        self.register_static_ui("launcher", cache_control="no-store")
        self.logger.info("Budget widget: UI registered")
        try:
            widget = self.show_widget()
        except OSError:
            widget = {"shown": False, "reason": "桌面挂件未能启动，请查看插件面板"}
        return Ok({"panel": "http://127.0.0.1:48923", "widget": widget})

    @lifecycle(id="shutdown")
    async def shutdown(self, **_):
        if self.recording:
            result = await asyncio.to_thread(self.recording.action, "end")
            if result.get("summary"):
                self.announce(result["summary"])
        if self.widget and self.widget.poll() is None:
            if sys.platform == "win32":
                self.stop_file.touch()
            else:
                self.widget.terminate()
            try:
                await asyncio.to_thread(self.widget.wait, 3)
            except subprocess.TimeoutExpired:
                self.widget.kill()
                await asyncio.to_thread(self.widget.wait)
        self.widget = None
        if self.recording:
            await asyncio.to_thread(self.recording.close)
        if self.server:
            await asyncio.to_thread(self.server.shutdown)
            self.server.server_close()
            await asyncio.to_thread(self.server_thread.join, 3)
            self.server = None
        if self.monitor:
            await asyncio.to_thread(self.monitor.close)
            self.monitor = None
        return Ok({"stopped": True})

    @plugin_entry(
        id="get_balance",
        name="猫粮还剩多少",
        description="查询用户配置的猫粮余额或预算。estimated_tokens 仅为按用户价格估算；stale 为真时必须说明结果已过期，不可称为实时余额。",
    )
    async def get_balance(self, **_):
        if self.monitor is None:
            return Ok({"message": "请先启动猫粮余额插件"})
        return Ok(await asyncio.to_thread(self.monitor.refresh))

    @plugin_entry(id="open_panel", name="打开猫粮面板", description="显示猫粮挂件，可在挂件菜单内设置账户。")
    async def open_panel(self, **_):
        return Ok(self.show_widget())

    @plugin_entry(
        id="show_widget",
        name="显示猫粮挂件",
        description="显示透明桌面猫娘和余额气泡。收起挂件后可通过这个入口重新打开。",
    )
    async def show_widget_entry(self, **_):
        if self.monitor is None:
            return Ok({"shown": False, "reason": "请先启动插件"})
        return Ok(self.show_widget())

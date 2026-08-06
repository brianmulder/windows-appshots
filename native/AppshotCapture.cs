using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WindowsAppshots
{
    internal static class NativeMethods
    {
        internal const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        internal const int PW_RENDERFULLCONTENT = 2;
        internal const int MOD_ALT = 0x0001;
        internal const int MOD_CONTROL = 0x0002;
        internal const int MOD_SHIFT = 0x0004;
        internal const int MOD_NOREPEAT = 0x4000;
        internal const int WM_HOTKEY = 0x0312;
        internal const int WM_APP_TRAY_STATE = 0x8001;
        internal const int WM_APP_TRAY_THEME = 0x8002;
        internal const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
        internal const uint WINEVENT_OUTOFCONTEXT = 0x0000;

        internal delegate void WinEventDelegate(
            IntPtr hook, uint eventType, IntPtr hwnd, int objectId,
            int childId, uint eventThread, uint eventTime);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        internal static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool RegisterHotKey(IntPtr hwnd, int id, int modifiers, int virtualKey);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnregisterHotKey(IntPtr hwnd, int id);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostMessage(
            IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        internal static extern IntPtr SetWinEventHook(
            uint eventMin, uint eventMax, IntPtr module,
            WinEventDelegate callback, uint processId, uint threadId, uint flags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnhookWinEvent(IntPtr hook);

        [DllImport("dwmapi.dll")]
        internal static extern int DwmGetWindowAttribute(
            IntPtr hwnd, int attribute, out NativeRect value, int valueSize);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeRect
    {
        internal int Left;
        internal int Top;
        internal int Right;
        internal int Bottom;
    }

    internal sealed class Options
    {
        internal string Mode = "capture";
        internal string Output;
        internal string StateRoot;
        internal long Hwnd;
        internal int MaxNodes = 5000;
        internal int MaxText = 200000;
        internal int MaxDepth = 40;
        internal int TimeoutMs = 15000;
        internal string TreeView = "control";
        internal bool Tray;
        internal bool NoHotkey;
    }

    internal sealed class WatcherState
    {
        public int Pid;
        public string ProcessStartedAt;
        public string Executable;
        public string Hotkey;
        public bool Tray;
        public string StartedAt;
    }

    internal sealed class WindowIdentity
    {
        public string Hwnd;
        public int ProcessId;
        public string ProcessName;
        public string ProcessStartedAt;
        public string Title;
        public string ObservedAt;
    }

    internal sealed class RectModel
    {
        public double X;
        public double Y;
        public double Width;
        public double Height;
    }

    internal sealed class ElementModel
    {
        public int Id;
        public int? ParentId;
        public int Depth;
        public string ControlType;
        public string Name;
        public string AutomationId;
        public string ClassName;
        public string Framework;
        public bool Enabled;
        public bool Focused;
        public bool Offscreen;
        public bool Password;
        public RectModel Bounds;
        public string Value;
        public string Text;
        public List<string> Patterns = new List<string>();
        public string Error;
    }

    internal sealed class CaptureManifest
    {
        public string Schema = "windows-appshot/v1";
        public string CapturedAt;
        public WindowIdentity Window;
        public RectModel WindowBounds;
        public string Visual = "visual.png";
        public string AccessibilityTree = "accessibility-tree.json";
        public string AccessibleText = "accessible-text.txt";
        public string ModelContext = "model-context.md";
        public int NodeCount;
        public bool Truncated;
        public string TreeView;
        public CaptureLimits Limits;
        public List<string> Warnings = new List<string>();
        public CredentialRedactionReceipt CredentialRedaction;
    }

    internal sealed class CaptureLimits
    {
        public int MaxNodes;
        public int MaxText;
        public int MaxDepth;
        public int TimeoutMs;
    }

    internal sealed class CaptureResult
    {
        internal CaptureManifest Manifest;
        internal List<ElementModel> Elements = new List<ElementModel>();
        internal StringBuilder Text = new StringBuilder();
        internal DateTime Deadline;
        internal Options Options;
        internal bool Truncated;
        internal CredentialRedactor Redactor;
    }

    internal static class Json
    {
        internal static readonly JavaScriptSerializer Serializer =
            new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 512 };

        internal static string Encode(object value)
        {
            return Serializer.Serialize(value);
        }

        internal static T Decode<T>(string value)
        {
            return Serializer.Deserialize<T>(value);
        }
    }

    internal static class Program
    {
        private static readonly string[] ExcludedProcesses =
            { "chatgpt", "codex", "appshotcapture", "windowsappshots" };

        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                Options options = ParseOptions(args);
                if (options.Mode == "watch")
                {
                    return RunWatch(options);
                }
                if (options.Mode == "capture")
                {
                    string bundle = CaptureOnMta(options);
                    Console.Out.WriteLine(Json.Encode(new { ok = true, bundle = bundle }));
                    return 0;
                }
                if (options.Mode == "capture-bounded")
                {
                    Console.Out.WriteLine(RunCaptureBounded(options));
                    return 0;
                }
                if (options.Mode == "stop")
                {
                    Console.Out.WriteLine(Json.Encode(StopWatcher(options.StateRoot)));
                    return 0;
                }
                if (options.Mode == "watcher-status")
                {
                    Console.Out.WriteLine(Json.Encode(GetWatcherStatus(options.StateRoot)));
                    return 0;
                }
                if (options.Mode == "foreground")
                {
                    WindowIdentity identity = SanitizeWindow(
                        DescribeWindow(NativeMethods.GetForegroundWindow()),
                        new CredentialRedactor());
                    Console.Out.WriteLine(Json.Encode(identity));
                    return 0;
                }

                throw new ArgumentException("Unknown mode: " + options.Mode);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(Json.Encode(new
                {
                    ok = false,
                    error = CredentialRedactor.SanitizeDiagnostic(ex.Message),
                    detail = CredentialRedactor.SanitizeDiagnostic(ex.ToString())
                }));
                return 1;
            }
        }

        private static Options ParseOptions(string[] args)
        {
            Options value = new Options();
            int index = 0;
            if (args.Length > 0 && !args[0].StartsWith("--", StringComparison.Ordinal))
            {
                value.Mode = args[0].ToLowerInvariant();
                index = 1;
            }

            while (index < args.Length)
            {
                string key = args[index++];
                if (index >= args.Length)
                {
                    throw new ArgumentException("Missing value for " + key);
                }
                string item = args[index++];
                switch (key)
                {
                    case "--output": value.Output = item; break;
                    case "--state-root": value.StateRoot = item; break;
                    case "--hwnd": value.Hwnd = ParseHwnd(item); break;
                    case "--max-nodes": value.MaxNodes = int.Parse(item, CultureInfo.InvariantCulture); break;
                    case "--max-text": value.MaxText = int.Parse(item, CultureInfo.InvariantCulture); break;
                    case "--max-depth": value.MaxDepth = int.Parse(item, CultureInfo.InvariantCulture); break;
                    case "--timeout-ms": value.TimeoutMs = int.Parse(item, CultureInfo.InvariantCulture); break;
                    case "--tree-view": value.TreeView = item.ToLowerInvariant(); break;
                    case "--tray": value.Tray = ParseBool(item, key); break;
                    case "--no-hotkey": value.NoHotkey = ParseBool(item, key); break;
                    default: throw new ArgumentException("Unknown option: " + key);
                }
            }
            if (value.TreeView != "raw" && value.TreeView != "control" && value.TreeView != "content")
            {
                throw new ArgumentException("--tree-view must be raw, control, or content.");
            }

            if (string.IsNullOrEmpty(value.StateRoot))
            {
                value.StateRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "WindowsAppshots");
            }
            return value;
        }

        private static bool ParseBool(string value, string key)
        {
            bool parsed;
            if (!bool.TryParse(value, out parsed))
                throw new ArgumentException(key + " must be true or false.");
            return parsed;
        }

        private static long ParseHwnd(string value)
        {
            if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            {
                return long.Parse(value.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            }
            return long.Parse(value, CultureInfo.InvariantCulture);
        }

        private static string RunCaptureBounded(Options options)
        {
            List<string> args = new List<string>
            {
                "capture",
                "--state-root", options.StateRoot,
                "--max-nodes", options.MaxNodes.ToString(CultureInfo.InvariantCulture),
                "--max-text", options.MaxText.ToString(CultureInfo.InvariantCulture),
                "--max-depth", options.MaxDepth.ToString(CultureInfo.InvariantCulture),
                "--timeout-ms", options.TimeoutMs.ToString(CultureInfo.InvariantCulture),
                "--tree-view", options.TreeView
            };
            if (options.Hwnd != 0)
            {
                args.Add("--hwnd");
                args.Add(options.Hwnd.ToString(CultureInfo.InvariantCulture));
            }
            if (!string.IsNullOrEmpty(options.Output))
            {
                args.Add("--output");
                args.Add(options.Output);
            }

            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = Assembly.GetExecutingAssembly().Location,
                Arguments = JoinArguments(args),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using (Process child = new Process { StartInfo = start })
            {
                StringBuilder stdout = new StringBuilder();
                StringBuilder stderr = new StringBuilder();
                child.OutputDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (eventArgs.Data != null) stdout.AppendLine(eventArgs.Data);
                };
                child.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (eventArgs.Data != null) stderr.AppendLine(eventArgs.Data);
                };
                child.Start();
                child.BeginOutputReadLine();
                child.BeginErrorReadLine();
                int outerTimeout = Math.Max(1000, options.TimeoutMs + 2000);
                if (!child.WaitForExit(outerTimeout))
                {
                    try { child.Kill(); }
                    catch (Exception) { }
                    child.WaitForExit();
                    throw new TimeoutException(
                        "UI Automation capture exceeded " + outerTimeout.ToString(CultureInfo.InvariantCulture) +
                        " ms and its isolated worker process was stopped.");
                }
                child.WaitForExit();
                if (child.ExitCode != 0)
                {
                    string diagnostic = stderr.ToString().Trim();
                    if (diagnostic.Length == 0) diagnostic = stdout.ToString().Trim();
                    throw new InvalidOperationException(
                        diagnostic.Length == 0 ? "Capture worker failed." : diagnostic);
                }
                string output = stdout.ToString().Trim();
                if (output.Length == 0) throw new InvalidOperationException("Capture worker returned no result.");
                return output;
            }
        }

        private static string CaptureOnMta(Options options)
        {
            string bundle = null;
            Exception failure = null;
            Thread worker = new Thread(new ThreadStart(delegate
            {
                try { bundle = Capture(options); }
                catch (Exception ex) { failure = ex; }
            }));
            worker.IsBackground = true;
            worker.SetApartmentState(ApartmentState.MTA);
            worker.Start();
            worker.Join();
            if (failure != null) throw new InvalidOperationException(failure.Message, failure);
            return bundle;
        }

        private static string JoinArguments(IEnumerable<string> values)
        {
            List<string> quoted = new List<string>();
            foreach (string value in values) quoted.Add(QuoteArgument(value));
            return string.Join(" ", quoted.ToArray());
        }

        private static string QuoteArgument(string value)
        {
            if (value == null) return "\"\"";
            StringBuilder output = new StringBuilder("\"");
            int slashes = 0;
            foreach (char item in value)
            {
                if (item == '\\')
                {
                    slashes++;
                    continue;
                }
                if (item == '"')
                {
                    output.Append('\\', slashes * 2 + 1);
                    output.Append('"');
                    slashes = 0;
                    continue;
                }
                output.Append('\\', slashes);
                slashes = 0;
                output.Append(item);
            }
            output.Append('\\', slashes * 2);
            output.Append('"');
            return output.ToString();
        }

        private static string Capture(Options options)
        {
            Directory.CreateDirectory(options.StateRoot);
            IntPtr hwnd = options.Hwnd != 0
                ? new IntPtr(options.Hwnd)
                : ReadLastForeground(options.StateRoot);

            if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd))
            {
                throw new InvalidOperationException(
                    "No capturable foreground window is known. Focus the target app and try again.");
            }

            CredentialRedactor redactor = new CredentialRedactor();
            WindowIdentity window = SanitizeWindow(DescribeWindow(hwnd), redactor);
            if (window == null)
            {
                throw new InvalidOperationException("The target window disappeared before capture.");
            }

            string finalOutput = options.Output;
            if (string.IsNullOrEmpty(finalOutput))
            {
                finalOutput = Path.Combine(options.StateRoot, "captures",
                    DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ", CultureInfo.InvariantCulture));
            }
            finalOutput = Path.GetFullPath(finalOutput);
            if (Directory.Exists(finalOutput) || File.Exists(finalOutput))
                throw new IOException("The capture output path already exists.");
            string parent = Path.GetDirectoryName(finalOutput);
            if (string.IsNullOrEmpty(parent))
                throw new IOException("The capture output path has no parent directory.");
            Directory.CreateDirectory(parent);
            string staging = finalOutput + ".partial-" + Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(staging);
            try
            {
                NativeRect nativeBounds = GetBounds(hwnd);
                RectModel bounds = ToRect(nativeBounds);
                CaptureManifest manifest = new CaptureManifest
                {
                    CapturedAt = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                    Window = window,
                    WindowBounds = bounds,
                    TreeView = options.TreeView,
                    Limits = new CaptureLimits
                    {
                        MaxNodes = options.MaxNodes,
                        MaxText = options.MaxText,
                        MaxDepth = options.MaxDepth,
                        TimeoutMs = options.TimeoutMs
                    }
                };

                string visualPath = Path.Combine(staging, manifest.Visual);
                try
                {
                    CaptureVisual(hwnd, nativeBounds, visualPath);
                }
                catch (Exception ex)
                {
                    manifest.Warnings.Add(redactor.Redact(
                        "Visual capture failed: " + ex.Message, false));
                }

                CaptureResult result = new CaptureResult
                {
                    Manifest = manifest,
                    Deadline = DateTime.UtcNow.AddMilliseconds(options.TimeoutMs),
                    Options = options,
                    Redactor = redactor
                };

                try
                {
                    AutomationElement root = AutomationElement.FromHandle(hwnd);
                    if (root != null)
                    {
                        WalkElement(root, null, 0, result);
                    }
                    else
                    {
                        manifest.Warnings.Add("UI Automation returned no root element.");
                    }
                }
                catch (CredentialRedactionException) { throw; }
                catch (Exception ex)
                {
                    manifest.Warnings.Add(redactor.Redact(
                        "Accessibility capture failed: " + ex.Message, false));
                }

                manifest.NodeCount = result.Elements.Count;
                manifest.Truncated = result.Truncated;
                manifest.CredentialRedaction = redactor.Complete();

                File.WriteAllText(
                    Path.Combine(staging, manifest.AccessibilityTree),
                    Json.Encode(new
                    {
                        schema = "windows-appshot/accessibility-v1",
                        rootWindow = window,
                        nodes = result.Elements
                    }),
                    new UTF8Encoding(false));
                File.WriteAllText(
                    Path.Combine(staging, manifest.AccessibleText),
                    result.Text.ToString(),
                    new UTF8Encoding(false));
                File.WriteAllText(
                    Path.Combine(staging, manifest.ModelContext),
                    BuildModelContext(manifest, result.Elements, result.Text.ToString()),
                    new UTF8Encoding(false));
                File.WriteAllText(
                    Path.Combine(staging, "manifest.json"),
                    Json.Encode(manifest),
                    new UTF8Encoding(false));

                Directory.Move(staging, finalOutput);
                WriteAtomicText(
                    Path.Combine(options.StateRoot, "latest-capture.json"),
                    Json.Encode(new { bundle = finalOutput, capturedAt = manifest.CapturedAt }));
                return finalOutput;
            }
            finally
            {
                if (Directory.Exists(staging))
                    Directory.Delete(staging, true);
            }
        }

        private static void WalkElement(
            AutomationElement element, int? parentId, int depth, CaptureResult result)
        {
            if (DateTime.UtcNow > result.Deadline ||
                result.Elements.Count >= result.Options.MaxNodes ||
                depth > result.Options.MaxDepth)
            {
                result.Truncated = true;
                return;
            }

            ElementModel node = ReadElement(element, parentId, depth, result);
            result.Elements.Add(node);

            AutomationElement child = null;
            TreeWalker walker = GetWalker(result.Options.TreeView);
            try { child = walker.GetFirstChild(element); }
            catch (ElementNotAvailableException) { return; }
            catch (UnauthorizedAccessException) { return; }

            while (child != null)
            {
                WalkElement(child, node.Id, depth + 1, result);
                if (result.Truncated && result.Elements.Count >= result.Options.MaxNodes) return;
                AutomationElement next = null;
                try { next = walker.GetNextSibling(child); }
                catch (ElementNotAvailableException) { return; }
                catch (UnauthorizedAccessException) { return; }
                child = next;
            }
        }

        private static TreeWalker GetWalker(string view)
        {
            if (view == "raw") return TreeWalker.RawViewWalker;
            if (view == "content") return TreeWalker.ContentViewWalker;
            return TreeWalker.ControlViewWalker;
        }

        private static ElementModel ReadElement(
            AutomationElement element, int? parentId, int depth, CaptureResult result)
        {
            ElementModel node = new ElementModel
            {
                Id = result.Elements.Count + 1,
                ParentId = parentId,
                Depth = depth
            };

            try
            {
                AutomationElement.AutomationElementInformation current = element.Current;
                node.ControlType = current.ControlType == null ? null : current.ControlType.ProgrammaticName;
                if (node.ControlType != null)
                {
                    node.ControlType = node.ControlType.Replace("ControlType.", "");
                }
                node.Name = result.Redactor.Redact(Clean(current.Name, 4000), false);
                node.AutomationId = result.Redactor.Redact(Clean(current.AutomationId, 1000), false);
                node.ClassName = result.Redactor.Redact(Clean(current.ClassName, 1000), false);
                node.Framework = result.Redactor.Redact(Clean(current.FrameworkId, 1000), false);
                node.Enabled = current.IsEnabled;
                node.Focused = current.HasKeyboardFocus;
                node.Offscreen = current.IsOffscreen;
                node.Password = current.IsPassword;
                node.Bounds = new RectModel
                {
                    X = current.BoundingRectangle.X,
                    Y = current.BoundingRectangle.Y,
                    Width = current.BoundingRectangle.Width,
                    Height = current.BoundingRectangle.Height
                };

                AddPattern(element, InvokePattern.Pattern, "Invoke", node);
                AddPattern(element, SelectionItemPattern.Pattern, "SelectionItem", node);
                AddPattern(element, ExpandCollapsePattern.Pattern, "ExpandCollapse", node);
                AddPattern(element, TogglePattern.Pattern, "Toggle", node);
                AddPattern(element, ScrollPattern.Pattern, "Scroll", node);
                AddPattern(element, ValuePattern.Pattern, "Value", node);
                AddPattern(element, TextPattern.Pattern, "Text", node);

                if (!node.Password)
                {
                    bool labelledSecret = CredentialRedactor.IsCredentialLabel(
                        node.Name, node.AutomationId);
                    object pattern;
                    if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern))
                    {
                        node.Value = result.Redactor.Redact(
                            Clean(((ValuePattern)pattern).Current.Value, 16000), labelledSecret);
                    }
                    if (element.TryGetCurrentPattern(TextPattern.Pattern, out pattern) &&
                        result.Text.Length < result.Options.MaxText)
                    {
                        int remaining = result.Options.MaxText - result.Text.Length;
                        string text = ((TextPattern)pattern).DocumentRange.GetText(remaining);
                        text = result.Redactor.Redact(Clean(text, remaining), labelledSecret);
                        if (!string.IsNullOrWhiteSpace(text))
                        {
                            node.Text = text;
                            result.Text.AppendLine("[node " + node.Id + " " + (node.Name ?? node.ControlType) + "]");
                            result.Text.AppendLine(text);
                            result.Text.AppendLine();
                        }
                    }
                }
            }
            catch (CredentialRedactionException) { throw; }
            catch (Exception ex)
            {
                node.Error = result.Redactor.Redact(
                    ex.GetType().Name + ": " + ex.Message, false);
            }
            return node;
        }

        private static void AddPattern(
            AutomationElement element, AutomationPattern pattern, string name, ElementModel node)
        {
            object value;
            try
            {
                if (element.TryGetCurrentPattern(pattern, out value)) node.Patterns.Add(name);
            }
            catch (Exception) { }
        }

        private static string Clean(string value, int max)
        {
            if (string.IsNullOrEmpty(value)) return value;
            value = value.Replace("\0", "");
            return value.Length <= max ? value : value.Substring(0, max) + "…";
        }

        private static WindowIdentity SanitizeWindow(
            WindowIdentity identity, CredentialRedactor redactor)
        {
            if (identity == null) return null;
            identity.ProcessName = redactor.Redact(identity.ProcessName, false);
            identity.Title = redactor.Redact(identity.Title, false);
            return identity;
        }

        private static void WriteAtomicText(string path, string value)
        {
            string temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllText(temp, value, new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temp, path, null);
                else File.Move(temp, path);
            }
            finally
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
        }

        private static string BuildModelContext(
            CaptureManifest manifest, List<ElementModel> elements, string text)
        {
            StringBuilder output = new StringBuilder();
            output.AppendLine("# Windows AppShot");
            output.AppendLine();
            output.AppendLine("- Application: " + manifest.Window.ProcessName);
            output.AppendLine("- Window: " + manifest.Window.Title);
            output.AppendLine("- Captured: " + manifest.CapturedAt);
            output.AppendLine("- Elements: " + manifest.NodeCount);
            output.AppendLine("- Truncated: " + manifest.Truncated.ToString().ToLowerInvariant());
            output.AppendLine();
            output.AppendLine("## Interactive and informative controls");
            output.AppendLine();

            int written = 0;
            foreach (ElementModel node in elements)
            {
                bool interesting = !string.IsNullOrWhiteSpace(node.Name) ||
                    !string.IsNullOrWhiteSpace(node.Value) ||
                    node.Patterns.Count > 0;
                if (!interesting || node.Password) continue;

                output.Append("- ").Append(node.ControlType ?? "Element");
                if (!string.IsNullOrWhiteSpace(node.Name))
                    output.Append(" \"").Append(OneLine(node.Name, 300)).Append("\"");
                if (!string.IsNullOrWhiteSpace(node.Value))
                    output.Append(", value \"").Append(OneLine(node.Value, 300)).Append("\"");
                if (!node.Enabled) output.Append(", disabled");
                if (node.Offscreen) output.Append(", offscreen");
                if (node.Patterns.Count > 0)
                    output.Append(", patterns: ").Append(string.Join(", ", node.Patterns.ToArray()));
                output.AppendLine();
                if (++written >= 1000)
                {
                    output.AppendLine("- …control summary truncated");
                    break;
                }
            }

            if (!string.IsNullOrWhiteSpace(text))
            {
                output.AppendLine();
                output.AppendLine("## Exposed document text");
                output.AppendLine();
                output.AppendLine(text.Length > 50000 ? text.Substring(0, 50000) + "\n…text truncated" : text);
            }

            if (manifest.Warnings.Count > 0)
            {
                output.AppendLine();
                output.AppendLine("## Capture warnings");
                output.AppendLine();
                foreach (string warning in manifest.Warnings) output.AppendLine("- " + warning);
            }
            return output.ToString();
        }

        private static string OneLine(string value, int max)
        {
            value = value.Replace("\r", " ").Replace("\n", " ");
            return value.Length <= max ? value : value.Substring(0, max) + "…";
        }

        private static NativeRect GetBounds(IntPtr hwnd)
        {
            NativeRect bounds;
            int result = NativeMethods.DwmGetWindowAttribute(
                hwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS,
                out bounds, Marshal.SizeOf(typeof(NativeRect)));
            if (result != 0 || bounds.Right <= bounds.Left || bounds.Bottom <= bounds.Top)
            {
                AutomationElement element = AutomationElement.FromHandle(hwnd);
                if (element == null) throw new InvalidOperationException("Could not determine window bounds.");
                System.Windows.Rect rect = element.Current.BoundingRectangle;
                bounds.Left = (int)Math.Floor(rect.Left);
                bounds.Top = (int)Math.Floor(rect.Top);
                bounds.Right = (int)Math.Ceiling(rect.Right);
                bounds.Bottom = (int)Math.Ceiling(rect.Bottom);
            }
            return bounds;
        }

        private static RectModel ToRect(NativeRect value)
        {
            return new RectModel
            {
                X = value.Left,
                Y = value.Top,
                Width = value.Right - value.Left,
                Height = value.Bottom - value.Top
            };
        }

        private static void CaptureVisual(IntPtr hwnd, NativeRect bounds, string path)
        {
            int width = Math.Max(1, bounds.Right - bounds.Left);
            int height = Math.Max(1, bounds.Bottom - bounds.Top);
            using (Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                IntPtr hdc = graphics.GetHdc();
                bool printed;
                try { printed = NativeMethods.PrintWindow(hwnd, hdc, NativeMethods.PW_RENDERFULLCONTENT); }
                finally { graphics.ReleaseHdc(hdc); }

                if (!printed || LooksBlank(bitmap))
                {
                    graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0,
                        new Size(width, height), CopyPixelOperation.SourceCopy);
                    bitmap.Save(path, ImageFormat.Png);
                    return;
                }

                // PrintWindow from a DPI-virtualized target can render the real
                // window into the top-left of a physically sized bitmap. Trim
                // only the uniform black padding it leaves outside that image.
                Rectangle content = FindPrintedContent(bitmap);
                if (content.Width > 0 && content.Height > 0 &&
                    (content.Width < bitmap.Width || content.Height < bitmap.Height))
                {
                    using (Bitmap cropped = bitmap.Clone(content, bitmap.PixelFormat))
                    {
                        cropped.Save(path, ImageFormat.Png);
                    }
                }
                else
                {
                    bitmap.Save(path, ImageFormat.Png);
                }
            }
        }

        private static unsafe Rectangle FindPrintedContent(Bitmap bitmap)
        {
            int maxX = -1;
            int maxY = -1;
            Rectangle bounds = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            BitmapData data = bitmap.LockBits(
                bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte* firstRow = (byte*)data.Scan0.ToPointer();
                for (int y = bitmap.Height - 1; y >= 0 && maxY < 0; y--)
                {
                    byte* row = firstRow + (y * data.Stride);
                    for (int x = 0; x < bitmap.Width; x++)
                    {
                        byte* pixel = row + (x * 4);
                        if (pixel[3] != 0 &&
                            (pixel[2] > 3 || pixel[1] > 3 || pixel[0] > 3))
                        {
                            maxY = y;
                            break;
                        }
                    }
                }
                for (int x = bitmap.Width - 1; x >= 0 && maxX < 0; x--)
                {
                    for (int y = 0; y <= maxY; y++)
                    {
                        byte* pixel = firstRow + (y * data.Stride) + (x * 4);
                        if (pixel[3] != 0 &&
                            (pixel[2] > 3 || pixel[1] > 3 || pixel[0] > 3))
                        {
                            maxX = x;
                            break;
                        }
                    }
                }
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
            return maxX < 0 || maxY < 0 ? Rectangle.Empty : new Rectangle(0, 0, maxX + 1, maxY + 1);
        }

        private static bool LooksBlank(Bitmap bitmap)
        {
            Color first = bitmap.GetPixel(0, 0);
            int samples = 0;
            int different = 0;
            int xStep = Math.Max(1, bitmap.Width / 12);
            int yStep = Math.Max(1, bitmap.Height / 12);
            for (int y = 0; y < bitmap.Height; y += yStep)
            {
                for (int x = 0; x < bitmap.Width; x += xStep)
                {
                    samples++;
                    Color color = bitmap.GetPixel(x, y);
                    if (Math.Abs(color.R - first.R) + Math.Abs(color.G - first.G) +
                        Math.Abs(color.B - first.B) > 8) different++;
                }
            }
            return samples == 0 || different < 2;
        }

        private static WindowIdentity DescribeWindow(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return null;
            uint pid;
            NativeMethods.GetWindowThreadProcessId(hwnd, out pid);
            StringBuilder title = new StringBuilder(4096);
            NativeMethods.GetWindowText(hwnd, title, title.Capacity);
            string processName = "unknown";
            string processStartedAt = null;
            try
            {
                using (Process process = Process.GetProcessById((int)pid))
                {
                    processName = process.ProcessName;
                    processStartedAt = process.StartTime.ToUniversalTime().ToString(
                        "o", CultureInfo.InvariantCulture);
                }
            }
            catch (Exception) { }
            return new WindowIdentity
            {
                Hwnd = "0x" + hwnd.ToInt64().ToString("X", CultureInfo.InvariantCulture),
                ProcessId = (int)pid,
                ProcessName = processName,
                ProcessStartedAt = processStartedAt,
                Title = title.ToString(),
                ObservedAt = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)
            };
        }

        private static bool IsExcluded(WindowIdentity identity)
        {
            if (identity == null || string.IsNullOrWhiteSpace(identity.Title)) return true;
            string process = (identity.ProcessName ?? "").ToLowerInvariant();
            foreach (string excluded in ExcludedProcesses)
            {
                if (process.Contains(excluded)) return true;
            }
            return false;
        }

        private static IntPtr ReadLastForeground(string stateRoot)
        {
            string path = Path.Combine(stateRoot, "last-foreground.json");
            if (File.Exists(path))
            {
                try
                {
                    WindowIdentity value = Json.Decode<WindowIdentity>(File.ReadAllText(path));
                    IntPtr remembered;
                    if (MatchesRememberedWindow(value, out remembered)) return remembered;
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException(
                        "The remembered foreground-window identity is unreadable. " +
                        "Focus the target application again before capturing.", ex);
                }
                throw new InvalidOperationException(
                    "The remembered foreground window no longer matches its recorded process identity. " +
                    "Focus the target application again before capturing.");
            }
            IntPtr current = NativeMethods.GetForegroundWindow();
            WindowIdentity identity = DescribeWindow(current);
            return IsExcluded(identity) ? IntPtr.Zero : current;
        }

        private static bool MatchesRememberedWindow(
            WindowIdentity expected, out IntPtr hwnd)
        {
            hwnd = IntPtr.Zero;
            if (expected == null || string.IsNullOrEmpty(expected.Hwnd) ||
                expected.ProcessId <= 0 || string.IsNullOrEmpty(expected.ProcessName) ||
                string.IsNullOrEmpty(expected.ProcessStartedAt)) return false;

            IntPtr candidate = new IntPtr(ParseHwnd(expected.Hwnd));
            WindowIdentity current = DescribeWindow(candidate);
            if (current == null) return false;
            if (current.ProcessId != expected.ProcessId) return false;
            if (!string.Equals(current.ProcessName, expected.ProcessName,
                StringComparison.OrdinalIgnoreCase)) return false;
            if (!string.Equals(current.ProcessStartedAt, expected.ProcessStartedAt,
                StringComparison.Ordinal)) return false;

            hwnd = candidate;
            return true;
        }

        private static int RunWatch(Options options)
        {
            Directory.CreateDirectory(options.StateRoot);
            using (ForegroundWatcher watcher = new ForegroundWatcher(options))
            {
                watcher.Run();
            }
            return 0;
        }

        private static object GetWatcherStatus(string stateRoot)
        {
            WatcherState state;
            Process process;
            string reason;
            bool running = TryGetWatcher(stateRoot, out state, out process, out reason);
            if (process != null) process.Dispose();
            return new
            {
                ok = true,
                running = running,
                pid = state == null ? 0 : state.Pid,
                tray = state != null && state.Tray,
                reason = reason
            };
        }

        private static object StopWatcher(string stateRoot)
        {
            WatcherState state;
            Process process;
            string reason;
            if (!TryGetWatcher(stateRoot, out state, out process, out reason))
            {
                DeleteWatcherState(stateRoot);
                return new { ok = true, stopped = false, pid = state == null ? 0 : state.Pid, reason = reason };
            }

            int pid = state.Pid;
            using (process)
            {
                process.Kill();
                if (!process.WaitForExit(5000))
                    throw new InvalidOperationException("The verified watcher process did not stop within 5 seconds.");
            }
            DeleteWatcherState(stateRoot);
            return new { ok = true, stopped = true, pid = pid };
        }

        private static bool TryGetWatcher(
            string stateRoot, out WatcherState state, out Process process, out string reason)
        {
            state = null;
            process = null;
            reason = "No watcher state exists.";
            string path = Path.Combine(stateRoot, "watcher.json");
            if (!File.Exists(path)) return false;
            try
            {
                state = Json.Decode<WatcherState>(File.ReadAllText(path));
                if (state == null || state.Pid <= 0 ||
                    string.IsNullOrEmpty(state.ProcessStartedAt) ||
                    string.IsNullOrEmpty(state.Executable))
                {
                    reason = "Watcher state is incomplete.";
                    return false;
                }
                process = Process.GetProcessById(state.Pid);
                string startedAt = process.StartTime.ToUniversalTime().ToString(
                    "o", CultureInfo.InvariantCulture);
                string executable = Path.GetFullPath(process.MainModule.FileName);
                if (!string.Equals(startedAt, state.ProcessStartedAt, StringComparison.Ordinal) ||
                    !string.Equals(executable, Path.GetFullPath(state.Executable),
                        StringComparison.OrdinalIgnoreCase))
                {
                    reason = "Watcher PID belongs to a different process identity.";
                    process.Dispose();
                    process = null;
                    return false;
                }
                reason = null;
                return true;
            }
            catch (Exception ex)
            {
                if (process != null) process.Dispose();
                process = null;
                reason = "Watcher is not running: " + ex.Message;
                return false;
            }
        }

        private static void DeleteWatcherState(string stateRoot)
        {
            try { File.Delete(Path.Combine(stateRoot, "watcher.json")); }
            catch (Exception) { }
        }

        internal sealed class ForegroundWatcher : NativeWindow, IDisposable
        {
            private enum TrayVisualState { Idle, Capturing, Success, Error }

            private readonly Options options;
            private readonly NativeMethods.WinEventDelegate callback;
            private IntPtr hook;
            private IntPtr lastWindow;
            private NotifyIcon trayIcon;
            private Icon trayImage;
            private TrayVisualState trayState;
            private int captureRunning;
            private bool hotkeyRegistered;
            private const int HotkeyId = 0x4150;

            internal ForegroundWatcher(Options options)
            {
                this.options = options;
                this.callback = OnForegroundChanged;
                CreateHandle(new CreateParams());
            }

            internal void Run()
            {
                hook = NativeMethods.SetWinEventHook(
                    NativeMethods.EVENT_SYSTEM_FOREGROUND,
                    NativeMethods.EVENT_SYSTEM_FOREGROUND,
                    IntPtr.Zero, callback, 0, 0, NativeMethods.WINEVENT_OUTOFCONTEXT);
                if (hook == IntPtr.Zero) throw new InvalidOperationException("Could not install foreground-window hook.");

                if (!options.NoHotkey)
                {
                    hotkeyRegistered = NativeMethods.RegisterHotKey(
                        Handle, HotkeyId,
                        NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT |
                        NativeMethods.MOD_SHIFT | NativeMethods.MOD_NOREPEAT,
                        (int)Keys.A);
                    if (!hotkeyRegistered && !options.Tray) throw new InvalidOperationException(
                        "Could not register Ctrl+Alt+Shift+A. Another application may own it.");
                }

                if (options.Tray)
                {
                    CreateTrayIcon();
                    if (!options.NoHotkey && !hotkeyRegistered)
                    {
                        trayIcon.ShowBalloonTip(4000, "Windows AppShots",
                            "The global hotkey is unavailable. Capture remains available through Codex.",
                            ToolTipIcon.Warning);
                    }
                }

                Remember(NativeMethods.GetForegroundWindow());
                using (Process current = Process.GetCurrentProcess())
                {
                File.WriteAllText(Path.Combine(options.StateRoot, "watcher.json"),
                    Json.Encode(new WatcherState
                    {
                        Pid = current.Id,
                        ProcessStartedAt = current.StartTime.ToUniversalTime().ToString(
                            "o", CultureInfo.InvariantCulture),
                        Executable = current.MainModule.FileName,
                        Hotkey = hotkeyRegistered ? "Ctrl+Alt+Shift+A" : null,
                        Tray = options.Tray,
                        StartedAt = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)
                    }), new UTF8Encoding(false));
                }
                Application.Run();
            }

            private void CreateTrayIcon()
            {
                ContextMenu menu = new ContextMenu();
                menu.MenuItems.Add(new MenuItem("Open captures folder", delegate
                {
                    string captures = Path.Combine(options.StateRoot, "captures");
                    Directory.CreateDirectory(captures);
                    Process.Start("explorer.exe", QuoteArgument(captures));
                }));
                menu.MenuItems.Add("-");
                menu.MenuItems.Add(new MenuItem("Exit Windows AppShots", delegate
                {
                    Application.ExitThread();
                }));
                trayIcon = new NotifyIcon
                {
                    Text = "Windows AppShots",
                    ContextMenu = menu,
                    Visible = false
                };
                SetTrayState(TrayVisualState.Idle);
                trayIcon.Visible = true;
                SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
            }

            private void OnUserPreferenceChanged(
                object sender, UserPreferenceChangedEventArgs eventArgs)
            {
                NativeMethods.PostMessage(
                    Handle, NativeMethods.WM_APP_TRAY_THEME, IntPtr.Zero, IntPtr.Zero);
            }

            private void QueueTrayState(TrayVisualState state)
            {
                if (trayIcon == null) return;
                NativeMethods.PostMessage(
                    Handle, NativeMethods.WM_APP_TRAY_STATE,
                    new IntPtr((int)state), IntPtr.Zero);
            }

            private void SetTrayState(TrayVisualState state)
            {
                if (trayIcon == null) return;
                trayState = state;
                string theme = SystemTrayUsesLightTheme() ? "light" : "dark";
                string resource = "WindowsAppshots.Assets.tray-" +
                    state.ToString().ToLowerInvariant() + "-on-" + theme + ".ico";
                Icon next = null;
                using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
                {
                    if (stream != null) next = new Icon(stream);
                }
                if (next == null) next = (Icon)SystemIcons.Application.Clone();
                Icon previous = trayImage;
                trayImage = next;
                trayIcon.Icon = trayImage;
                if (previous != null) previous.Dispose();
            }

            private static bool SystemTrayUsesLightTheme()
            {
                try
                {
                    using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                        @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                    {
                        object value = key == null ? null : key.GetValue("SystemUsesLightTheme");
                        return value is int && (int)value != 0;
                    }
                }
                catch (Exception) { return false; }
            }

            private void OnForegroundChanged(
                IntPtr eventHook, uint eventType, IntPtr hwnd, int objectId,
                int childId, uint eventThread, uint eventTime)
            {
                Remember(hwnd);
            }

            private void Remember(IntPtr hwnd)
            {
                try
                {
                    WindowIdentity identity = SanitizeWindow(
                        DescribeWindow(hwnd), new CredentialRedactor());
                    if (IsExcluded(identity)) return;
                    lastWindow = hwnd;
                    WriteAtomicText(
                        Path.Combine(options.StateRoot, "last-foreground.json"),
                        Json.Encode(identity));
                }
                catch (Exception) { }
            }

            protected override void WndProc(ref Message message)
            {
                if (message.Msg == NativeMethods.WM_APP_TRAY_STATE)
                {
                    SetTrayState((TrayVisualState)message.WParam.ToInt32());
                    return;
                }
                if (message.Msg == NativeMethods.WM_APP_TRAY_THEME)
                {
                    SetTrayState(trayState);
                    return;
                }
                if (message.Msg == NativeMethods.WM_HOTKEY && message.WParam.ToInt32() == HotkeyId)
                {
                    BeginCapture();
                }
                base.WndProc(ref message);
            }

            private void BeginCapture()
            {
                if (Interlocked.CompareExchange(ref captureRunning, 1, 0) != 0) return;
                QueueTrayState(TrayVisualState.Capturing);
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try
                    {
                        lastWindow = ReadLastForeground(options.StateRoot);
                        Options capture = new Options
                        {
                            Mode = "capture-bounded",
                            StateRoot = options.StateRoot,
                            Hwnd = lastWindow.ToInt64(),
                            MaxNodes = options.MaxNodes,
                            MaxText = options.MaxText,
                            MaxDepth = options.MaxDepth,
                            TimeoutMs = options.TimeoutMs,
                            TreeView = options.TreeView
                        };
                        RunCaptureBounded(capture);
                        QueueTrayState(TrayVisualState.Success);
                        System.Media.SystemSounds.Asterisk.Play();
                        if (trayIcon != null) trayIcon.ShowBalloonTip(
                            1500, "Windows AppShots", "Capture saved.", ToolTipIcon.Info);
                    }
                    catch (Exception ex)
                    {
                        QueueTrayState(TrayVisualState.Error);
                        File.WriteAllText(Path.Combine(options.StateRoot, "last-error.json"),
                            Json.Encode(new
                            {
                                at = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                                error = CredentialRedactor.SanitizeDiagnostic(ex.Message)
                            }), new UTF8Encoding(false));
                        System.Media.SystemSounds.Hand.Play();
                        if (trayIcon != null) trayIcon.ShowBalloonTip(
                            3000, "Windows AppShots", "Capture failed. See last-error.json.", ToolTipIcon.Error);
                    }
                    finally
                    {
                        Interlocked.Exchange(ref captureRunning, 0);
                    }
                });
            }

            public void Dispose()
            {
                if (hotkeyRegistered) NativeMethods.UnregisterHotKey(Handle, HotkeyId);
                if (hook != IntPtr.Zero) NativeMethods.UnhookWinEvent(hook);
                if (trayIcon != null)
                {
                    SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
                    trayIcon.Visible = false;
                    trayIcon.Dispose();
                    trayIcon = null;
                }
                if (trayImage != null)
                {
                    trayImage.Dispose();
                    trayImage = null;
                }
                DeleteWatcherState(options.StateRoot);
                DestroyHandle();
            }
        }
    }
}

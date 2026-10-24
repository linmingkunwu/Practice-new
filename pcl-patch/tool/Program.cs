using System;
using System.Collections.Generic;
using System.Linq;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

static class Program
{
    const string GateMsg = "为遵守相关法律法规";
    const string PackLogSuffix = "ModModpack.vb";

    static int Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0] : "patch";
        string path = args.Length > 1 ? args[1] : @"E:\Git\pcl-patch\PCL_2.99.0.0_original.exe";
        string outPath = args.Length > 2 ? args[2] : path + ".patched";

        var mod = ModuleDefMD.Load(path);
        Console.WriteLine($"# module={mod.Name} asm={mod.Assembly?.FullName}");

        if (mode == "list")
        {
            var rx = new System.Text.RegularExpressions.Regex(args[2], System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (var t in mod.GetTypes().Where(t => rx.IsMatch(t.FullName)))
                foreach (var m in t.Methods)
                    Console.WriteLine($"{t.FullName}::{m.Name}\t{(m.HasBody ? m.Body.Instructions.Count + " instrs" : "no body")}\t{m.FullName}");
            return 0;
        }
        if (mode == "sig")
        {
            var rx = new System.Text.RegularExpressions.Regex(args[2], System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (var t in mod.GetTypes())
                foreach (var m in t.Methods)
                    if (rx.IsMatch(m.Name)) Console.WriteLine($"{t.Name}::{m.Name} :: {m.FullName}");
            return 0;
        }
        if (mode == "xref")
        {
            var needle = args[2];
            var seen = new HashSet<string>();
            foreach (var t in mod.GetTypes())
                foreach (var m in t.Methods)
                {
                    if (!m.HasBody) continue;
                    foreach (var i in m.Body.Instructions)
                        if (i.Operand is IMemberRef mr && mr.Name.String.Contains(needle) && seen.Add(mr.FullName))
                            Console.WriteLine($"[ref] {mr.FullName}\n      used in {t.FullName}::{m.Name}");
                }
            return 0;
        }
        if (mode == "il")
        {
            var tn = args[2]; var mn = args[3];
            int minIns = args.Length > 4 ? int.Parse(args[4]) : -1;
            var td = mod.Find(tn, false) ?? throw new Exception("type not found: " + tn);
            var md = td.Methods.Where(x => x.Name == mn && x.HasBody && (minIns < 0 || x.Body.Instructions.Count >= minIns)).FirstOrDefault()
                     ?? throw new Exception("method not found: " + mn);
            Console.WriteLine($"=== {td.FullName}::{mn} ret={md.ReturnType.FullName} params=[{string.Join(", ", md.Parameters.Select(p => p.Name + ":" + p.Type.FullName))}] ===");
            for (int vi = 0; vi < md.Body.Variables.Count; vi++) Console.WriteLine($"   V_{vi} : {md.Body.Variables[vi].Type.FullName}");
            foreach (var eh in md.Body.ExceptionHandlers)
                Console.WriteLine($"   {eh.HandlerType} try[{eh.TryStart?.Offset:x4}..{eh.TryEnd?.Offset:x4}] handler[{eh.HandlerStart?.Offset:x4}..{eh.HandlerEnd?.Offset:x4}]");
            foreach (var i in md.Body.Instructions) Console.WriteLine("  " + Fmt(i));
            return 0;
        }

        if (mode == "extract")
        {
            var dir = args[2];
            System.IO.Directory.CreateDirectory(dir);
            foreach (var r in mod.Resources)
            {
                if (r is EmbeddedResource er)
                {
                    var name = r.Name.String;
                    var fn = System.IO.Path.GetFileName(name);
                    var bytes = er.CreateReader().ToArray();
                    System.IO.File.WriteAllBytes(System.IO.Path.Combine(dir, fn), bytes);
                    Console.WriteLine($"# extracted {fn} ({bytes.Length} bytes)");
                }
            }
            return 0;
        }        if (mode == "p1v")
        {
            var variant = args[3];   // e.g. "full", "full-nomacro", "one", "one-log"
            var mt = mod.Find("PCL.ModModpack", false);
            var m3 = mt.Methods.First(x => x.Name == "ModpackInstall" && x.Parameters.Count == 3);
            var b = m3.Body;
            bool useMacro = !variant.Contains("nomacro");
            if (useMacro) b.SimplifyMacros(m3.Parameters);
            var ins = b.Instructions;
            int k = -1;
            for (int i = 0; i < ins.Count; i++) if (ins[i].OpCode == OpCodes.Ldstr && ins[i].Operand is string g && g.Contains(GateMsg)) { k = i; break; }
            if (k < 0) throw new Exception("gate not found");
            var loggerInfo = FindCallWith(mod, im => im.Name == "Info" && im.DeclaringType.Name.String == "Logger" && im.MethodSig.Params.Count == 3);
            string callerPath = ins.Cast<Instruction>().Where(x => x.OpCode == OpCodes.Ldstr && (x.Operand as string ?? "").EndsWith("ModModpack.vb")).Select(x => (string)x.Operand).First();
            var archiveLocal = b.Variables[1]; var baseLocal = b.Variables[2]; var packLocal = b.Variables[4];
            var tail0 = Instruction.Create(OpCodes.Ldloc, b.Variables[0]);
            var tail1 = Instruction.Create(OpCodes.Ret);
            IMethod M(string nm, int pc) => mt.Methods.First(x => x.Name == nm && x.MethodSig.Params.Count == pc);

            var seq = new List<Instruction>();
            void LogBlock(string log)
            {
                seq.Add(Instruction.Create(OpCodes.Ldstr, log));
                seq.Add(Instruction.Create(OpCodes.Ldc_I4_0));
                seq.Add(Instruction.Create(OpCodes.Ldstr, callerPath));
                seq.Add(Instruction.Create(OpCodes.Call, loggerInfo));
            }
            void CallBlock(string nm, int pc, bool inst, bool logo, bool log, string logText)
            {
                if (log) LogBlock(logText);
                seq.Add(Instruction.Create(OpCodes.Ldarg_0));
                seq.Add(Instruction.Create(OpCodes.Ldloc, archiveLocal));
                seq.Add(Instruction.Create(OpCodes.Ldloc, baseLocal));
                if (inst) seq.Add(Instruction.Create(OpCodes.Ldarg_1));
                if (logo) seq.Add(Instruction.Create(OpCodes.Ldarg_2));
                seq.Add(Instruction.Create(OpCodes.Call, M(nm, pc)));
                seq.Add(Instruction.Create(OpCodes.Stloc, b.Variables[0]));
                seq.Add(Instruction.Create(OpCodes.Leave, tail0));
            }

            if (variant.StartsWith("one"))
            {
                CallBlock("InstallPackCompress", 2, false, false, variant.Contains("log"), "整合包种类：未能识别，假定为压缩包");
            }
            else
            {
                var starts = new Instruction[7];
                void AddB(int slot, string nm, int pc, bool inst, bool logo, string logText)
                {
                    starts[slot] = seq.Count < seq.Count ? null : null;
                    starts[slot] = Instruction.Create(OpCodes.Nop); // placeholder, replaced below
                    int first = seq.Count;
                    CallBlock(nm, pc, inst, logo, true, logText);
                    starts[slot] = seq[first];
                }
                AddB(0, "InstallPackCurseForge", 5, true, true, "整合包种类：CurseForge");
                AddB(1, "InstallPackHMCL", 3, false, false, "整合包种类：HMCL");
                AddB(2, "InstallPackMMC", 3, false, false, "整合包种类：MMC");
                AddB(3, "InstallPackMCBBS", 4, true, false, "整合包种类：MCBBS");
                AddB(4, "InstallPackModrinth", 5, true, true, "整合包种类：Modrinth");
                AddB(5, "InstallPackCompress", 2, false, false, "整合包种类：未能识别，假定为压缩包");
                AddB(6, "InstallPackLauncherPack", 3, false, false, "整合包种类：带启动器的压缩包");
                var sw = Instruction.Create(OpCodes.Switch, new Instruction[10]);
                sw.Operand = new[] { starts[0], starts[1], starts[2], starts[3], starts[4], starts[5], starts[5], starts[5], starts[5], starts[6] };
                seq.Insert(0, sw);
                seq.Insert(0, Instruction.Create(OpCodes.Ldloc, packLocal));
                seq.Insert(2, Instruction.Create(OpCodes.Br, starts[5]));
            }

            ins[k].OpCode = seq[0].OpCode; ins[k].Operand = seq[0].Operand;
            for (int i = 1; i < seq.Count; i++) ins.Insert(k + i, seq[i]);
            int pad = k + seq.Count;
            ins[pad].OpCode = OpCodes.Nop; ins[pad].Operand = null;
            ins[pad + 1].OpCode = OpCodes.Leave; ins[pad + 1].Operand = tail0;
            ins.Add(tail0); ins.Add(tail1);
            var lf = b.ExceptionHandlers.OrderByDescending(h => h.HandlerStart.Offset).First();
            lf.HandlerEnd = tail0;
            b.MaxStack = 16;
            if (useMacro) b.OptimizeMacros();
            mod.Write(outPath);
            Console.WriteLine($"# p1v {variant} written ({seq.Count} dispatch instrs)");
            return 0;
        }        if (mode == "tailtest")
        {
            var what = args[3];   // "set" or "null"
            var mt = mod.Find("PCL.ModModpack", false);
            var m3 = mt.Methods.First(x => x.Name == "ModpackInstall" && x.Parameters.Count == 3);
            var b = m3.Body; var ins = b.Instructions;
            var tail0 = Instruction.Create(OpCodes.Ldloc_0);
            var tail1 = Instruction.Create(OpCodes.Ret);
            ins.Add(tail0); ins.Add(tail1);
            if (what == "set")
            {
                var lastFinally = b.ExceptionHandlers.OrderByDescending(h => h.HandlerStart.Offset).First();
                lastFinally.HandlerEnd = tail0;
            }
            b.MaxStack = 8;
            mod.Write(outPath);
            Console.WriteLine($"# tailtest {what} written");
            return 0;
        }        if (mode == "roundtrip")
        {
            mod.Write(outPath);
            Console.WriteLine($"# written (no changes): {outPath}");
            return 0;
        }        if (mode == "simplify")
        {
            var what = args[3];
            var mt = mod.Find("PCL.ModModpack", false);
            var m3 = mt.Methods.First(x => x.Name == "ModpackInstall" && x.Parameters.Count == 3);
            var b = m3.Body; var ins = b.Instructions;
            int n = 0;
            if (what == "nolog")
            {
                for (int i = 3; i < ins.Count; i++)
                    if (ins[i].OpCode.Name.StartsWith("call") && (ins[i].Operand as IMethod)?.Name == "Info" && (ins[i].Operand as IMethod)?.DeclaringType.Name.String == "Logger")
                    {
                        ins[i].OpCode = OpCodes.Nop; ins[i].Operand = null;
                        ins[i - 1].OpCode = OpCodes.Nop; ins[i - 1].Operand = null;
                        ins[i - 2].OpCode = OpCodes.Nop; ins[i - 2].Operand = null;
                        ins[i - 3].OpCode = OpCodes.Nop; ins[i - 3].Operand = null;
                        n++;
                    }
            }
            else if (what == "minimal")
            {
                // replace whole dispatch with: ldnull; stloc.0; leave <tail>
                int retIdx = -1;
                for (int i = ins.Count - 1; i >= 0; i--) if (ins[i].OpCode == OpCodes.Ret) { retIdx = i; break; }
                var tailInstr = ins[retIdx - 1];
                int startIdx = -1, endIdx = -1;
                for (int i = 0; i < ins.Count; i++) if (ins[i].OpCode == OpCodes.Switch) { startIdx = i - 1; endIdx = i; break; }
                if (startIdx < 0) throw new Exception("switch not found");
                for (int i = startIdx; i < retIdx - 1; i++) { ins[i].OpCode = OpCodes.Nop; ins[i].Operand = null; }
                ins[startIdx].OpCode = OpCodes.Ldnull;
                ins[startIdx + 1].OpCode = OpCodes.Stloc_0;
                ins[startIdx + 2].OpCode = OpCodes.Leave;
                ins[startIdx + 2].Operand = tailInstr;
                n++;
            }            else if (what == "popswitch")
            {
                for (int i = 0; i < ins.Count; i++) if (ins[i].OpCode == OpCodes.Switch) { ins[i].OpCode = OpCodes.Pop; ins[i].Operand = null; n++; }
            }
            else if (what == "noleave")
            {
                for (int i = 0; i < ins.Count; i++) if (ins[i].OpCode == OpCodes.Leave || ins[i].OpCode == OpCodes.Leave_S) { ins[i].OpCode = OpCodes.Ret; ins[i].Operand = null; n++; }
            }
            Console.WriteLine($"# simplify {what}: {n} site(s)");
            mod.Write(outPath);
            Console.WriteLine($"# written: {outPath}");
            return 0;
        }        if (mode == "patch2") { Patch2(mod, outPath); return 0; }
        if (mode == "inject")
        {
            string packPath = args[3];
            InjectTestCall(mod, packPath, outPath);
            return 0;
        }

        Console.WriteLine("unknown mode");
        return 1;
    }

    // ---------------- helpers ----------------
    static IMethod FindCallWith(ModuleDef mod, Func<IMethod, bool> pred)
    {
        foreach (var t in mod.GetTypes())
            foreach (var m in t.Methods)
            {
                if (!m.HasBody) continue;
                foreach (var i in m.Body.Instructions)
                    if ((i.OpCode.Name.StartsWith("call") || i.OpCode.Name == "newobj") && i.Operand is IMethod im && pred(im))
                        return im;
            }
        return null;
    }

    static IMethod LoggerInfo(ModuleDef mod) =>
        FindCallWith(mod, im => im.Name == "Info" && im.DeclaringType.Name.String == "Logger" && im.MethodSig != null && im.MethodSig.Params.Count == 3);

    static string CallerPathLiteral(MethodDef method, string suffix)
    {
        foreach (var i in method.Body.Instructions)
            if (i.OpCode == OpCodes.Ldstr && i.Operand is string s && s.EndsWith(suffix, StringComparison.Ordinal))
                return s;
        return null;
    }

    static void Patch2(ModuleDef mod, string outPath)
    {
        var modType = mod.Find("PCL.ModModpack", false) ?? throw new Exception("ModModpack type missing");
        var install3 = modType.Methods.First(m => m.Name == "ModpackInstall" && m.Parameters.Count == 3 && m.HasBody);
        var install0 = modType.Methods.First(m => m.Name == "ModpackInstall" && m.Parameters.Count == 0 && m.HasBody);
        var loggerInfo = LoggerInfo(mod) ?? throw new Exception("Logger.Info not found");
        var callerPath = CallerPathLiteral(install3, PackLogSuffix) ?? throw new Exception("caller path literal not found");

        // ---------- Patch 0a: download page -> real DlClientListLoader ----------
        var pageInstall = mod.Find("PCL.PageDownloadInstall", false) ?? throw new Exception("PageDownloadInstall missing");
        var loaderInit = pageInstall.FindMethod("LoaderInit") ?? throw new Exception("LoaderInit missing");
        var modDownload = mod.Find("PCL.ModDownload", false) ?? throw new Exception("ModDownload missing");
        var dlField = modDownload.FindField("DlClientListLoader") ?? throw new Exception("DlClientListLoader missing");
        var b0 = loaderInit.Body; b0.SimplifyMacros(loaderInit.Parameters);
        var i0 = b0.Instructions;
        int k0 = -1;
        for (int i = 0; i < i0.Count; i++) if (i0[i].OpCode == OpCodes.Ldstr && (i0[i].Operand as string) == "关闭下载") { k0 = i; break; }
        if (k0 < 0) throw new Exception("LoaderInit gate not found");
        int e0 = -1;
        for (int i = k0 + 1; i < i0.Count; i++)
            if (i0[i].OpCode == OpCodes.Newobj && i0[i].Operand is IMethod im0 && im0.DeclaringType.Name.String.Contains("LoaderTask")) { e0 = i; break; }
        if (e0 < 0) throw new Exception("LoaderTask ctor not found");
        i0[k0].OpCode = OpCodes.Ldsfld; i0[k0].Operand = dlField;
        for (int i = k0 + 1; i <= e0; i++) { i0[i].OpCode = OpCodes.Nop; i0[i].Operand = null; }
        b0.OptimizeMacros();
        Console.WriteLine("# patch0a ok: download page loader restored");

        // ---------- Patch 0b: modify page -> show Minecraft card ----------
        var pageModify = mod.Find("PCL.PageDownloadModify", false) ?? throw new Exception("PageDownloadModify missing");
        var lif = pageModify.FindMethod("LoadInstanceFinished") ?? throw new Exception("LoadInstanceFinished missing");
        var b0b = lif.Body; b0b.SimplifyMacros(lif.Parameters);
        var i0b = b0b.Instructions;
        int hit0b = 0;
        for (int i = 0; i + 2 < i0b.Count; i++)
            if (i0b[i].OpCode == OpCodes.Callvirt && (i0b[i].Operand as IMethod)?.Name == "get_CardMinecraft"
                && (i0b[i + 1].OpCode == OpCodes.Ldc_I4_2 || (i0b[i + 1].OpCode == OpCodes.Ldc_I4 && Convert.ToInt32(i0b[i + 1].Operand) == 2))
                && i0b[i + 2].OpCode == OpCodes.Callvirt && (i0b[i + 2].Operand as IMethod)?.Name == "set_Visibility")
            { i0b[i + 1].OpCode = OpCodes.Ldc_I4_0; i0b[i + 1].Operand = null; hit0b++; }
        if (hit0b == 0) throw new Exception("CardMinecraft visibility site not found");
        b0b.OptimizeMacros();
        Console.WriteLine("# patch0b ok: Minecraft card visible");
        // ---------- Patch 1: dispatch in ModpackInstall(File, InstanceName, Logo) ----------
        var body = install3.Body;
        body.SimplifyMacros(install3.Parameters);
        var ins = body.Instructions;
        int k = -1;
        for (int i = 0; i < ins.Count; i++)
            if (ins[i].OpCode == OpCodes.Ldstr && ins[i].Operand is string gs && gs.Contains(GateMsg)) { k = i; break; }
        if (k < 0) throw new Exception("dispatch gate throw not found");
        if (ins[k + 2].OpCode != OpCodes.Throw) throw new Exception("expected throw after Exception ctor");

        var retLocal = body.Variables[0];
        var archiveLocal = body.Variables[1];
        var baseFolderLocal = body.Variables[2];
        var packTypeLocal = body.Variables[4];

        IMethod M(string name, int pc) => modType.Methods.First(m => m.Name == name && m.MethodSig.Params.Count == pc);

        // tail instructions live outside the trailing finally handler
        var tail0 = Instruction.Create(OpCodes.Ldloc, retLocal);
        var tail1 = Instruction.Create(OpCodes.Ret);

        var seq = new List<Instruction>();
        var starts = new Instruction[7];
        void AddBlock(int slot, string log, IMethod target, bool instanceName = false, bool logo = false)
        {
            var list = new List<Instruction>
            {
                Instruction.Create(OpCodes.Ldstr, log), Instruction.Create(OpCodes.Ldc_I4_0), Instruction.Create(OpCodes.Ldstr, callerPath),
                Instruction.Create(OpCodes.Call, loggerInfo), Instruction.Create(OpCodes.Ldarg_0), Instruction.Create(OpCodes.Ldloc, archiveLocal),
                Instruction.Create(OpCodes.Ldloc, baseFolderLocal)
            };
            if (instanceName) list.Add(Instruction.Create(OpCodes.Ldarg_1));
            if (logo) list.Add(Instruction.Create(OpCodes.Ldarg_2));
            list.Add(Instruction.Create(OpCodes.Call, target));
            list.Add(Instruction.Create(OpCodes.Stloc, retLocal));
            list.Add(Instruction.Create(OpCodes.Leave, tail0));
            starts[slot] = list[0];
            seq.AddRange(list);
        }

        AddBlock(0, "整合包种类：CurseForge", M("InstallPackCurseForge", 5), instanceName: true, logo: true);
        AddBlock(1, "整合包种类：HMCL", M("InstallPackHMCL", 3));
        AddBlock(2, "整合包种类：MMC", M("InstallPackMMC", 3));
        AddBlock(3, "整合包种类：MCBBS", M("InstallPackMCBBS", 4), instanceName: true);
        AddBlock(4, "整合包种类：Modrinth", M("InstallPackModrinth", 5), instanceName: true, logo: true);
        AddBlock(5, "整合包种类：未能识别，假定为压缩包", M("InstallPackCompress", 2));
        AddBlock(6, "整合包种类：带启动器的压缩包", M("InstallPackLauncherPack", 3));

        var defStart = starts[5]; var launcherStart = starts[6];
        var switchInstr = Instruction.Create(OpCodes.Switch, new Instruction[10]);
        switchInstr.Operand = new[] { starts[0], starts[1], starts[2], starts[3], starts[4], defStart, defStart, defStart, defStart, launcherStart };
        seq.Insert(0, switchInstr);
        seq.Insert(0, Instruction.Create(OpCodes.Ldloc, packTypeLocal));
        seq.Insert(2, Instruction.Create(OpCodes.Br, defStart));   // PackType not in 0..9 -> Case Else

        // mutate the existing gate instructions instead of removing them:
        // some branches (Exit Try) target the first gate instruction.
        ins[k].OpCode = seq[0].OpCode; ins[k].Operand = seq[0].Operand;
        for (int i = 1; i < seq.Count; i++) ins.Insert(k + i, seq[i]);
        int pad = k + seq.Count;
        // the try block must not fall through its end: make the last gate slot a leave
        ins[pad].OpCode = OpCodes.Nop; ins[pad].Operand = null;
        ins[pad + 1].OpCode = OpCodes.Leave; ins[pad + 1].Operand = tail0;

        ins.Add(tail0);
        ins.Add(tail1);
        // the trailing finally handler must end before the ret, otherwise it swallows ldloc/ret
        var lastFinally2 = body.ExceptionHandlers.OrderByDescending(h => h.HandlerStart.Offset).First();
        if (lastFinally2.HandlerType != ExceptionHandlerType.Finally) throw new Exception("expected trailing finally");
        lastFinally2.HandlerEnd = tail0;

        body.MaxStack = 16;
        body.OptimizeMacros();
        Console.WriteLine($"# patch1 ok: dispatch restored at instr {k} ({seq.Count} instrs), ret target appended");

        // ---------- Patch 2: resource page install button ----------
        var detail = mod.Find("PCL.PageDownloadResourceDetail", false) ?? throw new Exception("PageDownloadResourceDetail missing");
        var initStack = detail.FindMethod("InitializeStackResourceVersions") ?? throw new Exception("InitializeStackResourceVersions missing");
        var installClick = detail.FindMethod("Install_Click");
        var saveClick = detail.FindMethod("Save_Click");
        var listItemHandler = mod.Find("PCL.MyListItem/ClickEventHandler", false)?.FindMethod(".ctor")
                              ?? throw new Exception("MyListItem/ClickEventHandler ctor missing");
        var iconHandler = mod.Find("PCL.MyIconButton/ClickEventHandler", false)?.FindMethod(".ctor")
                          ?? throw new Exception("MyIconButton/ClickEventHandler ctor missing");
        var b2 = initStack.Body; b2.SimplifyMacros(initStack.Parameters);
        var ins2 = b2.Instructions;
        int hit = 0;
        for (int i = 0; i + 2 < ins2.Count; i++)
        {
            if (ins2[i].OpCode != OpCodes.Ldftn || (ins2[i].Operand as IMethod)?.Name != "Save_Click") continue;
            if (ins2[i + 1].OpCode != OpCodes.Newobj || (ins2[i + 1].Operand as IMethod)?.DeclaringType.Name.String != "ClickEventHandler") continue;
            int ci = -1;
            for (int j = i + 2; j < Math.Min(ins2.Count, i + 8); j++)
                if (ins2[j].OpCode.Name != null && ins2[j].OpCode.Name.StartsWith("callvirt") && (ins2[j].Operand as IMethod)?.Name == "ToListItem") { ci = j; break; }
            if (ci < 0) continue;
            int nullIdx = -1;
            for (int j = i + 2; j < ci; j++) if (ins2[j].OpCode == OpCodes.Ldnull) { nullIdx = j; break; }
            if (nullIdx < 0) continue;
            ins2[i].Operand = installClick;                        // 1st handler = Install_Click
            ins2[nullIdx].OpCode = OpCodes.Ldarg_0; ins2[nullIdx].Operand = null;   // 2nd handler = Save_Click
            ins2.Insert(nullIdx + 1, Instruction.Create(OpCodes.Ldftn, saveClick));
            ins2.Insert(nullIdx + 2, Instruction.Create(OpCodes.Newobj, iconHandler));
            hit++;
            break;
        }
        if (hit == 0) throw new Exception("resource-page install button site not found");
        b2.MaxStack = 8; b2.OptimizeMacros();
        Console.WriteLine("# patch2 ok: resource page install button restored");

        // ---------- Patch 3: restore ModpackInstall() (choose file + RunInThread) ----------
        var closureType = mod.Find("PCL.ModModpack/_Closure$__0-0", false) ?? throw new Exception("closure 0-0 missing");
        var closureCtor = closureType.FindMethod(".ctor");
        var lambda = closureType.FindMethod("_Lambda$__0") ?? throw new Exception("closure lambda missing");
        var fileField = closureType.Fields.FirstOrDefault(f => f.Name.String.Contains("File")) ?? throw new Exception("closure File field missing");
        var selectFile = FindCallWith(mod, im => im.Name == "SelectFile" && im.DeclaringType.Name.String == "Dialogs")
                         ?? throw new Exception("Dialogs.SelectFile ref not found");
        var firstOrDefault = FindCallWith(mod, im => im.Name == "FirstOrDefault" && im.DeclaringType.Name.String == "Enumerable"
                                                     && im.MethodSig.Params.Count == 1 && im.MethodSig.Params[0].TypeName == "IEnumerable`1")
                             ?? throw new Exception("FirstOrDefault<String> ref not found");
        var isNullOrEmpty = FindCallWith(mod, im => im.Name == "IsNullOrEmpty" && im.DeclaringType.FullName == "System.String")
                            ?? throw new Exception("String.IsNullOrEmpty ref not found");
        var actionCtor = FindCallWith(mod, im => im.Name == ".ctor" && im.DeclaringType.FullName == "System.Action" && im.MethodSig.Params.Count == 2)
                         ?? throw new Exception("Action ctor ref not found");
        var modBase = mod.Find("PCL.ModBase", false) ?? throw new Exception("ModBase missing");
        var runInThread = modBase.Methods.First(m => m.Name == "RunInThread" && m.MethodSig.Params.Count == 1);

        var b3 = install0.Body;
        b3.Instructions.Clear();
        b3.ExceptionHandlers.Clear();
        b3.Variables.Clear();

        var vClosure = new Local(closureType.ToTypeSig());
        var vFile = new Local(mod.CorLibTypes.String);
        var filterSig = selectFile.MethodSig.Params[3];
        var vFilter = new Local(filterSig);
        b3.Variables.Add(vClosure); b3.Variables.Add(vFile); b3.Variables.Add(vFilter);

        var ni = b3.Instructions;
        ni.Add(Instruction.Create(OpCodes.Newobj, closureCtor));
        ni.Add(Instruction.Create(OpCodes.Stloc, vClosure));
        // File = Dialogs.SelectFile("选择整合包压缩文件", False, Nothing, Nothing).FirstOrDefault()
        ni.Add(Instruction.Create(OpCodes.Ldstr, "选择整合包压缩文件"));
        ni.Add(Instruction.Create(OpCodes.Ldc_I4_0));
        ni.Add(Instruction.Create(OpCodes.Ldnull));
        ni.Add(Instruction.Create(OpCodes.Ldloca, vFilter));
        ni.Add(Instruction.Create(OpCodes.Initobj, filterSig.ToTypeDefOrRef()));
        ni.Add(Instruction.Create(OpCodes.Ldloc, vFilter));
        ni.Add(Instruction.Create(OpCodes.Call, selectFile));
        ni.Add(Instruction.Create(OpCodes.Call, firstOrDefault));
        ni.Add(Instruction.Create(OpCodes.Stloc, vFile));
        // If String.IsNullOrEmpty(File) Then Return
        var retInstr = Instruction.Create(OpCodes.Ret);
        ni.Add(Instruction.Create(OpCodes.Ldloc, vFile));
        ni.Add(Instruction.Create(OpCodes.Call, isNullOrEmpty));
        ni.Add(Instruction.Create(OpCodes.Brtrue, retInstr));
        // closure.$VB$Local_File = File
        ni.Add(Instruction.Create(OpCodes.Ldloc, vClosure));
        ni.Add(Instruction.Create(OpCodes.Ldloc, vFile));
        ni.Add(Instruction.Create(OpCodes.Stfld, fileField));
        // RunInThread(New Action(closure, closure._Lambda$__0))
        ni.Add(Instruction.Create(OpCodes.Ldloc, vClosure));
        ni.Add(Instruction.Create(OpCodes.Ldftn, lambda));
        ni.Add(Instruction.Create(OpCodes.Newobj, actionCtor));
        ni.Add(Instruction.Create(OpCodes.Call, runInThread));
        ni.Add(retInstr);
        b3.MaxStack = 8;
        b3.OptimizeMacros();
        Console.WriteLine("# patch3 ok: ModpackInstall() entry restored (dialog + RunInThread)");

        mod.Write(outPath);
        Console.WriteLine($"# written: {outPath} ({new System.IO.FileInfo(outPath).Length} bytes)");
    }

    // inject a direct call to ModpackInstall into the --test automation lambda (test builds only)
    static void InjectTestCall(ModuleDef mod, string packPath, string outPath)
    {
        var modType = mod.Find("PCL.ModModpack", false) ?? throw new Exception("ModModpack missing");
        var install3 = modType.Methods.First(m => m.Name == "ModpackInstall" && m.Parameters.Count == 3 && m.HasBody);
        int endProgram = -1; MethodDef host = null;
        foreach (var t in mod.GetTypes())
        {
            if (!t.FullName.Contains("PageLaunchLeft")) continue;   // only the --test automation lambda
            foreach (var m in t.Methods)
            {
                if (!m.HasBody) continue;
                var ins = m.Body.Instructions;
                for (int i = 0; i + 1 < ins.Count; i++)
                {
                    int val = ins[i].OpCode == OpCodes.Ldc_I4_S ? (sbyte)ins[i].Operand
                             : ins[i].OpCode == OpCodes.Ldc_I4 ? Convert.ToInt32(ins[i].Operand) : -1;
                    if (val == 123 && ins[i + 1].OpCode.Name.StartsWith("call") && (ins[i + 1].Operand as IMethod)?.Name == "EndProgramForce")
                    { endProgram = i; host = m; break; }
                }
                if (host != null) break;
            }
            if (host != null) break;
        }
        if (host == null) throw new Exception("--test EndProgramForce(123) call site not found");
        var b = host.Body; b.SimplifyMacros(host.Parameters);
        var list = b.Instructions;
        var inserted = new List<Instruction>
        {
            Instruction.Create(OpCodes.Ldstr, packPath),
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Call, install3),
            Instruction.Create(OpCodes.Pop)
        };
        for (int i = 0; i < inserted.Count; i++) list.Insert(endProgram + i, inserted[i]);
        b.MaxStack = 16; b.OptimizeMacros();
        Console.WriteLine($"# inject ok: call into {host.DeclaringType.FullName}::{host.Name} at instr {endProgram}");
        mod.Write(outPath);
        Console.WriteLine($"# written: {outPath}");
    }

    static string Fmt(Instruction i)
    {
        string opnd = i.Operand switch
        {
            string s => "\"" + (s.Length > 70 ? s.Substring(0, 70) + "…" : s) + "\"",
            IMemberRef r => r.FullName,
            Instruction t => $"IL_{t.Offset:x4}",
            Instruction[] ts => string.Join(",", ts.Select(t => $"IL_{t.Offset:x4}")),
            null => "",
            _ => i.Operand.ToString()
        };
        return $"IL_{i.Offset:x4} {i.OpCode,-12} {opnd}";
    }
}

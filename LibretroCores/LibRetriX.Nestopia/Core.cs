﻿using LibRetriX.RetroBindings;
using System;
using System.Threading;

namespace LibRetriX
{
    internal static class NativeDllInfo
    {
        public const string DllName = nameof(Nestopia);
    }

    namespace Nestopia
    {
        public static class Core
        {
            private static Lazy<ICore> core = new Lazy<ICore>(InitCore, LazyThreadSafetyMode.ExecutionAndPublication);

            public static ICore Instance => core.Value;

            private static ICore InitCore()
            {
                var core = new LibretroCore(Dependencies);
                core.Initialize();
                return core;
            }

            private static readonly FileDependency[] Dependencies =
            {
                new FileDependency("disksys.rom", "Famicom Disk System BIOS", "ca30b50f880eb660a320674ed365ef7a"),
            };
        }
    }
}

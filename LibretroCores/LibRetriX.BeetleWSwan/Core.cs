﻿using LibRetriX.RetroBindings;
using System;
using System.Threading;

namespace LibRetriX
{
    internal static class NativeDllInfo
    {
        public const string DllName = nameof(BeetleWSwan);
    }

    namespace BeetleWSwan
    {
        public static class Core
        {
            private static Lazy<ICore> core = new Lazy<ICore>(InitCore, LazyThreadSafetyMode.ExecutionAndPublication);

            public static ICore Instance => core.Value;

            private static ICore InitCore()
            {
                var core = new LibretroCore();
                core.Initialize();
                return core;
            }
        }
    }
}

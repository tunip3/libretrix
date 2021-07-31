using LibRetriX.RetroBindings;
using LibRetriX.RetroBindings.Tools;
using System;
using System.Threading;

namespace LibRetriX
{
    internal static class NativeDllInfo
    {
        public const string DllName = nameof(VBAM);
    }

    namespace VBAM
    {
        public static class Core
        {
            private static Lazy<ICore> core = new Lazy<ICore>(InitCore, LazyThreadSafetyMode.ExecutionAndPublication);

            public static ICore Instance => core.Value;

            private static ICore InitCore()
            {
                var core = new LibretroCore(null, null, Converter.GenerateDeviceSubclass(Constants.RETRO_DEVICE_JOYPAD, 0));
                core.Initialize();
                return core;
            }
        }
    }
}

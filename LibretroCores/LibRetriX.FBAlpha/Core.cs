using LibRetriX.RetroBindings;
using System;
using System.Threading;

namespace LibRetriX
{
    internal static class NativeDllInfo
    {
        public const string DllName = nameof(FBAlpha);
    }

    namespace FBAlpha
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
                new FileDependency("neogeo.zip", "NeoGeo BIOS collection", "93adcaa22d652417cbc3927d46b11806"),
                new FileDependency("pgm.zip", "IGS PolyGame Master BIOS", "581cc172db39bb5007642405adf25b6e"),
            };
        }
    }
}

using LibRetriX.RetroBindings.Tools;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

namespace LibRetriX.RetroBindings
{
    internal sealed class LibretroCore : ICore, IDisposable
    {
        private const int AudioSamplesPerFrame = 2;

        public string Name { get; }
        public string Version { get; }
        public IReadOnlyList<string> SupportedExtensions { get; }
        public bool NativeArchiveSupport { get; }

        private bool RequiresFullPath { get; }

        private IntPtr CurrentlyResolvedCoreOptionValue { get; set; }
        public IReadOnlyDictionary<string, CoreOption> Options { get; private set; }

        private IReadOnlyList<Tuple<string, uint>> OptionSetters { get; }

        public IReadOnlyList<FileDependency> FileDependencies { get; }

        private IntPtr systemRootPathUnmanaged;
        private string systemRootPath;
        public string SystemRootPath
        {
            get => systemRootPath;
            set { SetStringAndUnmanagedMemory(value, ref systemRootPath, ref systemRootPathUnmanaged); }
        }

        private IntPtr saveRootPathUnmanaged;
        private string saveRootPath;
        public string SaveRootPath
        {
            get => saveRootPath;
            set { SetStringAndUnmanagedMemory(value, ref saveRootPath, ref saveRootPathUnmanaged); }
        }

        private PixelFormats pixelFormat;
        public PixelFormats PixelFormat
        {
            get => pixelFormat;
            private set { pixelFormat = value; PixelFormatChanged?.Invoke(pixelFormat); }
        }

        private GameGeometry geometry;
        public GameGeometry Geometry
        {
            get => geometry;
            private set { geometry = value; GeometryChanged?.Invoke(geometry); }
        }

        private SystemTimings timings;
        public SystemTimings Timings
        {
            get => timings;
            private set { timings = value; TimingsChanged?.Invoke(timings); }
        }

        private Rotations rotation;
        public Rotations Rotation
        {
            get => rotation;
            private set { rotation = value; RotationChanged?.Invoke(rotation); }
        }

        public ulong SerializationSize => (ulong)LibretroAPI.GetSerializationSize();

        public PollInputDelegate PollInput { get; set; }
        public GetInputStateDelegate GetInputState { get; set; }
        public OpenFileStreamDelegate OpenFileStream
        {
            get => VFSHandler.OpenFileStream;
            set { VFSHandler.OpenFileStream = value; }
        }

        public CloseFileStreamDelegate CloseFileStream
        {
            get => VFSHandler.CloseFileStream;
            set { VFSHandler.CloseFileStream = value; }
        }

        public event RenderVideoFrameDelegate RenderVideoFrame;
        public event RenderAudioFramesDelegate RenderAudioFrames;
        public event PixelFormatChangedDelegate PixelFormatChanged;
        public event GeometryChangedDelegate GeometryChanged;
        public event TimingsChangedDelegate TimingsChanged;
        public event RotationChangedDelegate RotationChanged;

        private static LogCallbackDescriptor LogCBDescriptor { get; } = new LogCallbackDescriptor { LogCallback = LogHandler };

        private List<List<ControllerDescription>> SupportedInputsPerPort { get; } = new List<List<ControllerDescription>>();
        private Lazy<uint[]> InputTypesToUse { get; }
        private IEnumerable<uint> PreferredInputTypes { get; }

        private bool IsInitialized { get; set; }
        private GameInfo? CurrentGameInfo { get; set; }
        private GCHandle GameDataHandle { get; set; }

        private readonly short[] RenderAudioFrameBuffer = new short[2];

        public LibretroCore(IReadOnlyList<FileDependency> dependencies = null, IReadOnlyList<Tuple<string, uint>> optionSetters = null, uint? inputTypeId = null)
        {
            FileDependencies = dependencies == null ? Array.Empty<FileDependency>() : dependencies;
            OptionSetters = optionSetters == null ? Array.Empty<Tuple<string, uint>>() : optionSetters;

            InputTypesToUse = new Lazy<uint[]>(DetermineInputTypesToUse, LazyThreadSafetyMode.PublicationOnly);
            var preferredInputTypes = new List<uint> { Constants.RETRO_DEVICE_ANALOG, Constants.RETRO_DEVICE_JOYPAD };
            PreferredInputTypes = preferredInputTypes;
            if (inputTypeId.HasValue)
            {
                preferredInputTypes.Insert(0, inputTypeId.Value);
            }

            var systemInfo = new SystemInfo();
            LibretroAPI.GetSystemInfo(ref systemInfo);
            Name = systemInfo.LibraryName;
            Version = systemInfo.LibraryVersion;
            SupportedExtensions = systemInfo.ValidExtensions.Split('|').Select(d => $".{d}").ToArray();
            NativeArchiveSupport = systemInfo.BlockExtract;
            RequiresFullPath = systemInfo.NeedFullpath;

            Options = new Dictionary<string, CoreOption>();
        }

        public void Dispose()
        {
            SystemRootPath = null;
            SaveRootPath = null;

            if (CurrentlyResolvedCoreOptionValue != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(CurrentlyResolvedCoreOptionValue);
                CurrentlyResolvedCoreOptionValue = IntPtr.Zero;
            }
        }

        public void Initialize()
        {
            LibretroAPI.EnvironmentCallback = EnvironmentHandler;
            LibretroAPI.RenderVideoFrameCallback = RenderVideoFrameHandler;
            LibretroAPI.RenderAudioFrameCallback = RenderAudioFrameHandler;
            LibretroAPI.RenderAudioFramesCallback = RenderAudioFramesHandler;
            LibretroAPI.PollInputCallback = PollInputHandler;
            LibretroAPI.GetInputStateCallback = GetInputStateHandler;
        }

        public bool LoadGame(string mainGameFilePath)
        {
            if (!IsInitialized)
            {
                LibretroAPI.Initialize();
                IsInitialized = true;
            }

            if (CurrentGameInfo.HasValue)
            {
                UnloadGameNoDeinit();
            }

            var gameInfo = new GameInfo()
            {
                Path = mainGameFilePath
            };

            if (!RequiresFullPath)
            {
                var stream = OpenFileStream?.Invoke(mainGameFilePath, FileAccess.Read);
                if (stream == null)
                {
                    return false;
                }

                var data = new byte[stream.Length];
                stream.Read(data, 0, data.Length);
                GameDataHandle = gameInfo.SetGameData(data);
                CloseFileStream(stream);
            }

            Rotation = Rotations.CCW0;

            var loadSuccessful = LibretroAPI.LoadGame(ref gameInfo);
            if (loadSuccessful)
            {
                var avInfo = new SystemAVInfo();
                LibretroAPI.GetSystemAvInfo(ref avInfo);

                Geometry = avInfo.Geometry;
                Timings = avInfo.Timings;

                var inputTypesToUse = InputTypesToUse.Value;
                for (var i = 0; i < inputTypesToUse.Length; i++)
                {
                    LibretroAPI.SetControllerPortDevice((uint)i, inputTypesToUse[i]);
                }

                CurrentGameInfo = gameInfo;
            }

            return CurrentGameInfo.HasValue;
        }

        public void UnloadGame()
        {
            UnloadGameNoDeinit();

            if (IsInitialized)
            {
                LibretroAPI.Cleanup();
                IsInitialized = false;
            }
        }

        public void Reset()
        {
            LibretroAPI.Reset();
        }

        public void RunFrame()
        {
            LibretroAPI.RunFrame();
        }

        public bool SaveState(Stream outputStream)
        {
            var size = LibretroAPI.GetSerializationSize();
            var stateData = new byte[(int)size];

            var handle = GCHandle.Alloc(stateData, GCHandleType.Pinned);
            var result = LibretroAPI.SaveState(handle.AddrOfPinnedObject(), (IntPtr)stateData.Length);
            handle.Free();

            if (result == true)
            {
                outputStream.Position = 0;
                outputStream.Write(stateData, 0, stateData.Length);
                outputStream.SetLength(stateData.Length);
            }

            return result;
        }

        public bool LoadState(Stream inputStream)
        {
            var stateData = new byte[inputStream.Length];
            inputStream.Position = 0;
            inputStream.Read(stateData, 0, stateData.Length);

            var handle = GCHandle.Alloc(stateData, GCHandleType.Pinned);
            var result = LibretroAPI.LoadState(handle.AddrOfPinnedObject(), (IntPtr)stateData.Length);
            handle.Free();

            return result;
        }

        private void UnloadGameNoDeinit()
        {
            if (!CurrentGameInfo.HasValue)
            {
                return;
            }

            LibretroAPI.UnloadGame();
            if (GameDataHandle.IsAllocated)
            {
                GameDataHandle.Free();
            }

            CurrentGameInfo = null;
        }

        private bool EnvironmentHandler(uint command, IntPtr dataPtr)
        {
            switch (command)
            {
                case Constants.RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
                    {
                        Marshal.StructureToPtr(LogCBDescriptor, dataPtr, false);
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_VARIABLES:
                    {
                        var newOptions = new Dictionary<string, CoreOption>();
                        Options = newOptions;

                        var data = Marshal.PtrToStructure<LibretroVariable>(dataPtr);
                        while (data.KeyPtr != IntPtr.Zero)
                        {
                            var key = Marshal.PtrToStringAnsi(data.KeyPtr);
                            var rawValue = Marshal.PtrToStringAnsi(data.ValuePtr);

                            var split = rawValue.Split(';');
                            var description = split[0];

                            rawValue = rawValue.Substring(description.Length + 2);
                            split = rawValue.Split('|');

                            newOptions.Add(key, new CoreOption(description, split));

                            dataPtr += Marshal.SizeOf<LibretroVariable>();
                            data = Marshal.PtrToStructure<LibretroVariable>(dataPtr);
                        }

                        foreach(var i in OptionSetters)
                        {
                            Options[i.Item1].SelectedValueIx = i.Item2;
                        }

                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_VARIABLE:
                    {
                        var data = Marshal.PtrToStructure<LibretroVariable>(dataPtr);
                        var key = Marshal.PtrToStringAnsi(data.KeyPtr);
                        var valueFound = false;
                        data.ValuePtr = IntPtr.Zero;

                        if (Options.ContainsKey(key))
                        {
                            valueFound = true;
                            var coreOption = Options[key];
                            var value = coreOption.Values[(int)coreOption.SelectedValueIx];
                            if (CurrentlyResolvedCoreOptionValue != IntPtr.Zero)
                            {
                                Marshal.FreeHGlobal(CurrentlyResolvedCoreOptionValue);
                            }

                            CurrentlyResolvedCoreOptionValue = Marshal.StringToHGlobalAnsi(value);
                            data.ValuePtr = CurrentlyResolvedCoreOptionValue;
                        }

                        Marshal.StructureToPtr(data, dataPtr, false);
                        return valueFound;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_OVERSCAN:
                    {
                        Marshal.WriteByte(dataPtr, 0);
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_CAN_DUPE:
                    {
                        Marshal.WriteByte(dataPtr, 1);
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
                    {
                        Marshal.WriteIntPtr(dataPtr, systemRootPathUnmanaged);
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
                    {
                        Marshal.WriteIntPtr(dataPtr, saveRootPathUnmanaged);
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
                    {
                        var data = (PixelFormats)Marshal.ReadInt32(dataPtr);
                        PixelFormat = data;
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_GEOMETRY:
                    {
                        var data = Marshal.PtrToStructure<GameGeometry>(dataPtr);
                        Geometry = data;
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_ROTATION:
                    {
                        var data = (Rotations)Marshal.ReadInt32(dataPtr);
                        Rotation = data;
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
                    {
                        var data = Marshal.PtrToStructure<SystemAVInfo>(dataPtr);
                        Geometry = data.Geometry;
                        Timings = data.Timings;
                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
                    {
                        IntPtr portDescriptionsPtr;
                        do
                        {
                            var portControllerData = Marshal.PtrToStructure<ControllerInfo>(dataPtr);
                            portDescriptionsPtr = portControllerData.DescriptionsPtr;
                            if (portDescriptionsPtr != IntPtr.Zero)
                            {
                                var currentPortDescriptions = new List<ControllerDescription>();
                                SupportedInputsPerPort.Add(currentPortDescriptions);
                                for (var i = 0U; i < portControllerData.NumDescriptions; i++)
                                {
                                    var nativeDescription = Marshal.PtrToStructure<ControllerDescription.NativeForm>(portDescriptionsPtr);
                                    currentPortDescriptions.Add(new ControllerDescription(nativeDescription));
                                    portDescriptionsPtr += Marshal.SizeOf<ControllerDescription.NativeForm>();
                                }

                                dataPtr += Marshal.SizeOf<ControllerInfo>();
                            }                 
                        }
                        while (portDescriptionsPtr != IntPtr.Zero);

                        return true;
                    }
                case Constants.RETRO_ENVIRONMENT_GET_VFS_INTERFACE:
                    {
                        var data = Marshal.PtrToStructure<VFSInterfaceInfo>(dataPtr);
                        if (data.RequiredInterfaceVersion <= VFSHandler.SupportedVFSVersion)
                        {
                            data.RequiredInterfaceVersion = VFSHandler.SupportedVFSVersion;
                            data.Interface = VFSHandler.VFSInterfacePtr;
                            Marshal.StructureToPtr(data, dataPtr, false);
                        }

                        return true;
                    }
                default:
                    {
                        return false;
                    }
            }
        }

        private static void LogHandler(LogLevels level, IntPtr format, IntPtr argAddresses)
        {
#if DEBUG
            var message = Marshal.PtrToStringAnsi(format);
            System.Diagnostics.Debug.WriteLine($"{NativeDllInfo.DllName}: {level} - {message}");
#endif
        }

        unsafe private void RenderVideoFrameHandler(IntPtr data, uint width, uint height, UIntPtr pitch)
        {
            var size = (int)height * (int)pitch;

            var payload = default(ReadOnlySpan<byte>);
            if (data != IntPtr.Zero)
            {
                payload = new ReadOnlySpan<byte>(data.ToPointer(), size);
            }
                
            RenderVideoFrame?.Invoke(payload, width, height, (uint)pitch);
        }

        private unsafe void RenderAudioFrameHandler(short left, short right)
        {
            RenderAudioFrameBuffer[0] = left;
            RenderAudioFrameBuffer[1] = right;
            RenderAudioFrames?.Invoke(RenderAudioFrameBuffer.AsSpan(), 1);
        }

        private unsafe UIntPtr RenderAudioFramesHandler(IntPtr data, UIntPtr numFrames)
        {
            var payload = new ReadOnlySpan<short>(data.ToPointer(), (int)numFrames * AudioSamplesPerFrame);
            var output = RenderAudioFrames?.Invoke(payload, (uint)numFrames);
            return (UIntPtr)output;
        }

        private void PollInputHandler()
        {
            PollInput?.Invoke();
        }

        private short GetInputStateHandler(uint port, uint device, uint index, uint id)
        {
            var inputType = Converter.ConvertToInputType(device, index, id);
            var result = GetInputState?.Invoke(port, inputType);
            return result ?? 0;
        }

        private void SetStringAndUnmanagedMemory(string newValue, ref string store, ref IntPtr unmanagedPtr)
        {
            store = newValue;
            if (unmanagedPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(unmanagedPtr);
                unmanagedPtr = IntPtr.Zero;
            }

            if (newValue != null)
            {
                unmanagedPtr = Marshal.StringToHGlobalAnsi(newValue);
            }
        }

        private uint[] DetermineInputTypesToUse()
        {
            var result = SupportedInputsPerPort.Select(supportedInputs =>
            {
                var output = (uint)Constants.RETRO_DEVICE_NONE;
                if (!supportedInputs.Any())
                {
                    return output;
                }

                output = supportedInputs.First().Id;
                var currentPortSupportedInputsIds = new HashSet<uint>(supportedInputs.Select(e => e.Id));
                foreach (var j in PreferredInputTypes)
                {
                    if (currentPortSupportedInputsIds.Contains(j))
                    {
                        output = j;
                        break;
                    }
                }

                return output;
            }).ToArray();

            return result;
        }
    }
}

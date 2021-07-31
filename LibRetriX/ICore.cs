using System;
using System.Collections.Generic;
using System.IO;

namespace LibRetriX
{
    /// <summary>
    /// Video frame render callbacks
    /// </summary>
    /// <param name="data">Framebuffer data. Only valid while inside the callback</param>
    /// <param name="width">Framebufer width in pixels</param>
    /// <param name="height">Framebuffer height in pixels</param>
    /// <param name="pitch">Number of bytes between horizontal lines (framebuffer is not always packed in memory)</param>
    public delegate void RenderVideoFrameDelegate(ReadOnlySpan<byte> data, uint width, uint height, uint pitch);

    /// <summary>
    /// Audio data render callback. Use to fill audio buffers of whatever playback mechanism the front end uses
    /// </summary>
    /// <param name="data">Audio data. Only valid while inside the callback</param>
    /// <param name="numFrames">The number of audio frames to render</param>
    /// <returns>The number of audio frames enqueued for rendering. Can be less than numFrames</returns>
    public delegate uint RenderAudioFramesDelegate(ReadOnlySpan<short> data, uint numFrames);

    public delegate void PollInputDelegate();
    public delegate short GetInputStateDelegate(uint port, InputTypes inputType);

    public delegate void GeometryChangedDelegate(GameGeometry geometry);
    public delegate void TimingsChangedDelegate(SystemTimings timing);
    public delegate void RotationChangedDelegate(Rotations rotation);
    public delegate void PixelFormatChangedDelegate(PixelFormats format);

    public delegate Stream OpenFileStreamDelegate(string path, FileAccess fileAccess);
    public delegate void CloseFileStreamDelegate(Stream stream);

    /// <summary>
    /// Interface for Libretro cores
    /// </summary>
    public interface ICore
    {
        string Name { get; }
        string Version { get; }
		IReadOnlyList<string> SupportedExtensions { get; }
        bool NativeArchiveSupport { get; }

        string SystemRootPath { get; set; }
        string SaveRootPath { get; set; }

        IReadOnlyDictionary<string, CoreOption> Options { get; }
        IReadOnlyList<FileDependency> FileDependencies { get; }

        PixelFormats PixelFormat { get; }
        GameGeometry Geometry { get; }
        SystemTimings Timings { get; }
        Rotations Rotation { get; }
        ulong SerializationSize { get; }

        bool LoadGame(string mainGameFilePath);
		void UnloadGame();

		void RunFrame();
		void Reset();

		bool SaveState(Stream outputStream);
		bool LoadState(Stream inputStream);

        event RenderVideoFrameDelegate RenderVideoFrame;
        event RenderAudioFramesDelegate RenderAudioFrames;
        event PixelFormatChangedDelegate PixelFormatChanged;
		event GeometryChangedDelegate GeometryChanged;
		event TimingsChangedDelegate TimingsChanged;
		event RotationChangedDelegate RotationChanged;

        PollInputDelegate PollInput { get; set; }
        GetInputStateDelegate GetInputState { get; set; }
        OpenFileStreamDelegate OpenFileStream { get; set; }
        CloseFileStreamDelegate CloseFileStream { get; set; }
    };
}

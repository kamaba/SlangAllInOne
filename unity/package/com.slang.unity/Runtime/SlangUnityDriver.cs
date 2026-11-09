using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.Rendering;

namespace SlangUnity
{
    // Thin Unity host for the SL class library. No API mapping, no log
    // forwarding, no per-frame callbacks: ONE native call returns the whole
    // object snapshot, which is applied to real UnityEngine objects here.
    [DefaultExecutionOrder(-1000)]
    public sealed class SlangUnityDriver : MonoBehaviour
    {
        private const int MaxObjects = 64;
        private const int Stride = 20;

        [SerializeField] private string moduleRelativePath = "Slang/HelloCube.module.slb";

        private readonly double[] buffer = new double[1 + Stride * MaxObjects];
        private readonly Dictionary<long, ObjectView> views = new Dictionary<long, ObjectView>();
        private string slbPath;
        private CommandBuffer commandBuffer;
        private Camera attachedCamera;

        private sealed class ObjectView
        {
            public GameObject go;
            public Transform transform;
            public Renderer renderer;
            public Camera camera;
            public AudioSource audio;
            public MaterialPropertyBlock block;
            public bool wasPlaying;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Bootstrap()
        {
            if (FindFirstObjectByType<SlangUnityDriver>() != null)
            {
                return;
            }
            GameObject host = new GameObject("SlangUnityDriver");
            host.AddComponent<SlangUnityDriver>();
        }

        private void Awake()
        {
            slbPath = Path.Combine(Application.streamingAssetsPath, moduleRelativePath);
        }

        private void Start()
        {
            Boot();
            RegisterNativeRenderEvent();
        }

        private void Boot()
        {
            int rc = SlangUnityNative.slu_boot(Encoding.UTF8.GetBytes(slbPath + "\0"));
            if (rc != 0)
            {
                Debug.LogError("[SlangUnity] slu_boot failed, rc=" + rc + ", path=" + slbPath);
            }
        }

        // Registered ONCE. The engine then invokes C++ on the render thread.
        private void RegisterNativeRenderEvent()
        {
            IntPtr callback = SlangUnityNative.slu_get_render_event_func();
            attachedCamera = Camera.main;
            if (callback == IntPtr.Zero || attachedCamera == null)
            {
                return;
            }
            commandBuffer = new CommandBuffer { name = "SlangUnity.NativeRenderEvent" };
            commandBuffer.IssuePluginEvent(callback, 1);
            attachedCamera.AddCommandBuffer(CameraEvent.AfterForwardOpaque, commandBuffer);
        }

        private void Update()
        {
            int flags = SlangUnityNative.FrameObjects(Time.deltaTime, buffer);
            if ((flags & 0x01) != 0)
            {
                Boot();
            }

            int count = (int)buffer[0];
            if (count > MaxObjects)
            {
                count = MaxObjects;
            }
            for (int i = 0; i < count; i++)
            {
                ApplyOne(1 + i * Stride);
            }
        }

        private void ApplyOne(int b)
        {
            long handle = (long)buffer[b];
            ObjectView view;
            if (!views.TryGetValue(handle, out view))
            {
                view = Bind(handle);
                if (view == null)
                {
                    return;
                }
            }

            Vector3 position = new Vector3(
                (float)buffer[b + 3], (float)buffer[b + 4], (float)buffer[b + 5]);
            Quaternion rotation = Quaternion.Euler(
                (float)buffer[b + 6], (float)buffer[b + 7], (float)buffer[b + 8]);
            view.transform.SetPositionAndRotation(position, rotation);
            view.transform.localScale = new Vector3(
                (float)buffer[b + 9], (float)buffer[b + 10], (float)buffer[b + 11]);

            int dirty = (int)buffer[b + 19];
            if ((dirty & 0x01) != 0 && view.renderer != null)
            {
                Color color = new Color(
                    (float)buffer[b + 12], (float)buffer[b + 13],
                    (float)buffer[b + 14], (float)buffer[b + 15]);
                view.block.SetColor("_Color", color);
                view.block.SetColor("_BaseColor", color);
                view.renderer.SetPropertyBlock(view.block);
            }
            if ((dirty & 0x02) != 0 && view.camera != null)
            {
                view.camera.fieldOfView = (float)buffer[b + 16];
            }
            if ((dirty & 0x04) != 0 && view.go != null)
            {
                view.go.SetActive(buffer[b + 1] != 0.0);
            }
            if (view.audio != null)
            {
                view.audio.volume = (float)buffer[b + 17];
                bool playing = buffer[b + 18] != 0.0;
                if (playing != view.wasPlaying)
                {
                    if (playing) { view.audio.Play(); }
                    else { view.audio.Stop(); }
                    view.wasPlaying = playing;
                }
            }
        }

        // Low-frequency path: only when a handle is seen for the first time.
        private ObjectView Bind(long handle)
        {
            string name = SlangUnityNative.ObjectName(handle);
            if (string.IsNullOrEmpty(name))
            {
                return null;
            }
            GameObject go = GameObject.Find(name);
            if (go == null)
            {
                go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.name = name;
            }
            ObjectView view = new ObjectView
            {
                go = go,
                transform = go.transform,
                renderer = go.GetComponent<Renderer>(),
                camera = go.GetComponent<Camera>(),
                audio = go.GetComponent<AudioSource>(),
                block = new MaterialPropertyBlock()
            };
            views[handle] = view;
            return view;
        }

        private void OnDestroy()
        {
            if (commandBuffer != null && attachedCamera != null)
            {
                attachedCamera.RemoveCommandBuffer(CameraEvent.AfterForwardOpaque, commandBuffer);
            }
            if (commandBuffer != null)
            {
                commandBuffer.Dispose();
                commandBuffer = null;
            }
        }
    }
}

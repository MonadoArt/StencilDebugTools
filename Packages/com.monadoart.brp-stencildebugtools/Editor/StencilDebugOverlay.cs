using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

#if UNITY_EDITOR
public class StencilDebugOverlayWindow : EditorWindow
{
    private static readonly float distance = 2f; // Distance in front of the Scene view camera
    private static readonly Vector2 size = new Vector2(10f, 10f); // Hardcoded size of the quad
    
    private Material quadMaterial;
    private GameObject quad;
    private Renderer quadRenderer;
    private Texture2D numberAtlas;

    // Material Controls
    private bool quadEnabled = true;
    private float tilingSlider = 0.7f; // Logarithmic slider, 0=min, 1=max, 0.7=default (32)
    private float opacity = 0.35f;
    private float rotation = 22.5f;
    private bool showNumbers = true;

    [MenuItem("Tools/StencilDebugTools/Stencil Debug Overlay", false, 10)]
    public static void ShowWindow()
    {
        var window = GetWindow<StencilDebugOverlayWindow>("Stencil Debug Overlay");
        window.minSize = new Vector2(400, 300);
    }

    private void OnEnable()
    {
        LoadNumberAtlas();
        CreateQuad();
        SceneView.duringSceneGui += UpdateQuadTransform;
        UpdateMaterialProperties();
    }

    private void OnDisable()
    {
        SceneView.duringSceneGui -= UpdateQuadTransform;
        if (quad != null)
        {
            DestroyImmediate(quad);
            quad = null;
        }
        if (quadMaterial != null)
        {
            DestroyImmediate(quadMaterial);
            quadMaterial = null;
        }
        quadRenderer = null;
    }

    private void LoadNumberAtlas()
    {
        if (numberAtlas == null)
        {
            numberAtlas = Resources.Load<Texture2D>("number_atlas_256");
            if (numberAtlas == null)
            {
                Debug.LogWarning("StencilDebugOverlay: Failed to load number_atlas_256 from Resources. Please assign it manually in the window.");
            }
        }
    }

    private void CreateQuad()
    {
        quad = GameObject.CreatePrimitive(PrimitiveType.Quad);
        quad.name = "SceneViewStencilDebugQuad";
        quad.hideFlags = HideFlags.HideAndDontSave;
        
        quadRenderer = quad.GetComponent<Renderer>();
        if (quadRenderer == null)
        {
            Debug.LogError("StencilDebugOverlay: Failed to get Renderer component from quad.");
            DestroyImmediate(quad);
            quad = null;
            return;
        }
        
        if (quadMaterial == null)
        {
            Shader shader = Shader.Find("Unlit/StencilDebugShader");
            if (shader == null)
            {
                Debug.LogError("StencilDebugOverlay: Shader 'Unlit/StencilDebugShader' not found. Please ensure the shader exists.");
                DestroyImmediate(quad);
                quad = null;
                quadRenderer = null;
                return;
            }
            quadMaterial = new Material(shader);
        }
        
        if (numberAtlas != null)
        {
            quadMaterial.SetTexture("_NumberAtlas", numberAtlas);
        }
        
        quadRenderer.material = quadMaterial;
        quad.SetActive(quadEnabled);
    }

    private void UpdateQuadTransform(SceneView sceneView)
    {
        Camera cam = sceneView.camera;
        if (cam == null || quad == null) return;
        quad.transform.position = cam.transform.position + cam.transform.forward * distance;
        quad.transform.rotation = cam.transform.rotation;
        quad.transform.localScale = new Vector3(size.x, size.y, 1f);
    }

    private void UpdateMaterialProperties()
    {
        if (quadMaterial == null) return;
        
        // Logarithmic mapping: 2 to 512
        float minTiling = 2f;
        float maxTiling = 512f;
        float logMin = Mathf.Log(minTiling, 2f);
        float logMax = Mathf.Log(maxTiling, 2f);
        float exponent = Mathf.Lerp(logMin, logMax, tilingSlider);
        float tilingAmount = Mathf.Round(Mathf.Pow(2f, exponent));
        
        quadMaterial.SetFloat("_TileCount", tilingAmount);
        quadMaterial.SetFloat("_BgOpacity", opacity);
        quadMaterial.SetFloat("_NumberRotation", rotation);
        quadMaterial.SetFloat("_ShowNumbers", showNumbers ? 1f : 0f);
    }

    private void OnGUI()
    {
        EditorGUILayout.LabelField("Stencil Debug Overlay", EditorStyles.boldLabel);
        EditorGUILayout.Space();

        // Quad Toggle
        EditorGUI.BeginChangeCheck();
        quadEnabled = EditorGUILayout.Toggle("Show Overlay", quadEnabled);
        if (EditorGUI.EndChangeCheck())
        {
            if (quad != null)
            {
                quad.SetActive(quadEnabled);
            }
        }

        EditorGUILayout.Space();

        // Number Atlas field
        EditorGUI.BeginChangeCheck();
        numberAtlas = (Texture2D)EditorGUILayout.ObjectField("Number Atlas", numberAtlas, typeof(Texture2D), false);
        if (EditorGUI.EndChangeCheck())
        {
            if (quadMaterial != null)
            {
                quadMaterial.SetTexture("_NumberAtlas", numberAtlas);
            }
        }

        EditorGUILayout.Space();

        // Tiling Slider
        EditorGUI.BeginChangeCheck();
        tilingSlider = EditorGUILayout.Slider("Tiling", tilingSlider, 0f, 1f);
        if (EditorGUI.EndChangeCheck())
        {
            UpdateMaterialProperties();
        }

        // Opacity Slider
        EditorGUI.BeginChangeCheck();
        opacity = EditorGUILayout.Slider("Opacity", opacity, 0f, 1f);
        if (EditorGUI.EndChangeCheck())
        {
            UpdateMaterialProperties();
        }

        // Rotation Slider
        EditorGUI.BeginChangeCheck();
        rotation = EditorGUILayout.Slider("Rotation", rotation, -180f, 180f);
        if (EditorGUI.EndChangeCheck())
        {
            UpdateMaterialProperties();
        }

        // Show Numbers Toggle
        EditorGUI.BeginChangeCheck();
        showNumbers = EditorGUILayout.Toggle("Show Numbers", showNumbers);
        if (EditorGUI.EndChangeCheck())
        {
            UpdateMaterialProperties();
        }

        EditorGUILayout.Space();

        // Opacity control buttons
        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("Opacity 0%"))
        {
            opacity = 0f;
            UpdateMaterialProperties();
        }
        if (GUILayout.Button("Opacity Default"))
        {
            opacity = 0.35f;
            UpdateMaterialProperties();
        }
        if (GUILayout.Button("Opacity 100%"))
        {
            opacity = 1f;
            UpdateMaterialProperties();
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        if (GUILayout.Button("⟲ Rotate -22.5°"))
        {
            rotation -= 22.5f;
            UpdateMaterialProperties();
        }
        if (GUILayout.Button("⟳ Rotate +22.5°"))
        {
            rotation += 22.5f;
            UpdateMaterialProperties();
        }
        EditorGUILayout.EndHorizontal();

        if (GUILayout.Button("Reset Material Controls"))
        {
            opacity = 0.35f;
            tilingSlider = 0.7f;
            rotation = 22.5f;
            showNumbers = true;
            UpdateMaterialProperties();
        }
    }
}
#endif

using UnityEditor;
using UnityEngine;

public class StencilCalculatorWindow : EditorWindow
{
    private const int ByteMin = 0;
    private const int ByteMax = 255;
    private const float LabelColumnWidth = 120f;
    private const float BinaryColumnWidth = 8 * 14f;
    private const float DecimalColumnWidth = 60f;
    private const float ColumnGap = 8f;

    private enum StencilCompareFunction
    {
        Disabled,
        Never,
        Less,
        Equal,
        LessEqual,
        Greater,
        NotEqual,
        GreaterEqual,
        Always
    }

    private enum StencilOp
    {
        Keep,
        Zero,
        Replace,
        IncrementSaturate,
        DecrementSaturate,
        Invert,
        IncrementWrap,
        DecrementWrap
    }

    private static readonly StencilOp[] StencilOpValues =
    {
        StencilOp.Keep,
        StencilOp.Zero,
        StencilOp.Replace,
        StencilOp.IncrementSaturate,
        StencilOp.DecrementSaturate,
        StencilOp.Invert,
        StencilOp.IncrementWrap,
        StencilOp.DecrementWrap
    };

    private static readonly string[] StencilOpLabels =
    {
        "Keep",
        "Zero",
        "Replace",
        "Increment Saturate",
        "Decrement Saturate",
        "Invert",
        "Increment Wrap",
        "Decrement Wrap"
    };

    private static readonly string[] CompareFuncLabels =
    {
        "Disabled",
        "Never",
        "Less",
        "Equal",
        "LessEqual",
        "Greater",
        "NotEqual",
        "GreaterEqual",
        "Always"
    };

    private StencilCompareFunction stencilCompareFunction = StencilCompareFunction.Always;
    private StencilOp stencilPassOp = StencilOp.Keep;
    private StencilOp stencilFailOp = StencilOp.Keep;
    private int initialValue;
    private int stencilRef;
    private int stencilReadMask = ByteMax;
    private int stencilWriteMask = ByteMax;

    private bool showReadMaskBits;
    private bool showWriteMaskBits;
    private bool showInitialValueBits;
    private bool showStencilRefBits;
    private float rowHeight;
    private GUIStyle bitMonoStyle;

    [MenuItem("Tools/StencilDebugTools/Stencil Calculator")]
    public static void ShowWindow() => GetWindow<StencilCalculatorWindow>("Stencil Calculator");

    private void OnEnable()
    {
        minSize = new Vector2(350f, 400f);
        bitMonoStyle = CreateBitStyle();
    }

    private void OnGUI()
    {
        GUILayout.Label("Stencil & Mask Binary Calculator", EditorStyles.boldLabel);

        initialValue = DrawByteControl("Initial Value", ref showInitialValueBits, initialValue);
        GUILayout.Space(2);
        stencilRef = DrawByteControl("Stencil Ref", ref showStencilRefBits, stencilRef);
        GUILayout.Space(2);
        stencilReadMask = DrawByteControl("Read Mask", ref showReadMaskBits, stencilReadMask);
        GUILayout.Space(2);
        stencilWriteMask = DrawByteControl("Write Mask", ref showWriteMaskBits, stencilWriteMask);

        GUILayout.Space(8);

        DrawStencilOperationControls();

        GUILayout.Space(10);

        if (bitMonoStyle == null)
        {
            bitMonoStyle = CreateBitStyle();
        }
        rowHeight = EditorGUIUtility.singleLineHeight;

        DrawColumnHeader();

        DrawBitButtonRow("Initial Value", ref initialValue, bitMonoStyle, null, Color.yellow);
        DrawBitButtonRow("Stencil Ref", ref stencilRef, bitMonoStyle, i => ((stencilReadMask >> i) & 1) == 1 ? Color.green : Color.gray);
        DrawBitButtonRow("Read Mask", ref stencilReadMask, bitMonoStyle, null, new Color(1f, 0.5f, 0.8f));

        int readMaskOutput = initialValue & stencilReadMask;
        DrawBitLabelRow("ReadMask Output", readMaskOutput, bitMonoStyle);

        GUILayout.Space(8);

        DrawBitButtonRow("Stencil Ref (Write)", ref stencilRef, bitMonoStyle, i => ((stencilWriteMask >> i) & 1) == 1 ? Color.green : Color.gray);
        DrawBitButtonRow("Write Mask", ref stencilWriteMask, bitMonoStyle, null, new Color(1f, 0.5f, 0.8f));

        int stencilTestValue = initialValue & stencilReadMask;
        int stencilRefMasked = stencilRef & stencilReadMask;
        bool stencilCheckPassed = EvaluateStencilCompare(stencilCompareFunction, stencilTestValue, stencilRefMasked);

        int opResult = stencilCheckPassed
            ? ApplyStencilOp(stencilPassOp, initialValue, stencilRef)
            : ApplyStencilOp(stencilFailOp, initialValue, stencilRef);

        int finalOutput = (opResult & stencilWriteMask) | (initialValue & ~stencilWriteMask);

        GUILayout.Space(8);

        DrawBitLabelRow("Final Output", finalOutput, bitMonoStyle);

        GUILayout.Space(12);

        DrawResultBanner(stencilCheckPassed);
    }

    private void DrawResultBanner(bool stencilCheckPassed)
    {
        Color backgroundColor = stencilCheckPassed
            ? new Color(0.13f, 0.41f, 0.17f)
            : new Color(0.45f, 0.07f, 0.07f);
        string label = stencilCheckPassed ? "STENCIL CHECK: PASS" : "STENCIL CHECK: FAIL";

        Rect bannerRect = GUILayoutUtility.GetRect(GUIContent.none, GUIStyle.none, GUILayout.Height(36f));
        EditorGUI.DrawRect(bannerRect, backgroundColor);

        GUIStyle textStyle = new GUIStyle(EditorStyles.boldLabel)
        {
            alignment = TextAnchor.MiddleCenter,
            fontSize = 14
        };
        textStyle.normal.textColor = Color.white;
        textStyle.hover.textColor = Color.white;
        textStyle.active.textColor = Color.white;
        textStyle.focused.textColor = Color.white;

        GUI.Label(bannerRect, label, textStyle);
    }

    private void DrawColumnHeader()
    {
        GUILayout.BeginHorizontal();
        GUILayout.Label("Label", GUILayout.Width(LabelColumnWidth), GUILayout.Height(rowHeight));
        GUILayout.Label("Binary", GUILayout.Width(BinaryColumnWidth), GUILayout.Height(rowHeight));
        GUILayout.Space(ColumnGap);
        GUILayout.Label("Decimal", GUILayout.Width(DecimalColumnWidth), GUILayout.Height(rowHeight));
        GUILayout.EndHorizontal();
    }

    private void DrawStencilOperationControls()
    {
        int selectedPassIndex = Mathf.Clamp(System.Array.IndexOf(StencilOpValues, stencilPassOp), 0, StencilOpValues.Length - 1);
        int newPassIndex = EditorGUILayout.Popup("Stencil Pass Op", selectedPassIndex, StencilOpLabels);
        stencilPassOp = StencilOpValues[newPassIndex];

        int selectedFailIndex = Mathf.Clamp(System.Array.IndexOf(StencilOpValues, stencilFailOp), 0, StencilOpValues.Length - 1);
        int newFailIndex = EditorGUILayout.Popup("Stencil Fail Op", selectedFailIndex, StencilOpLabels);
        stencilFailOp = StencilOpValues[newFailIndex];

        int selectedCompare = EditorGUILayout.Popup("Stencil Compare Function", (int)stencilCompareFunction, CompareFuncLabels);
        stencilCompareFunction = (StencilCompareFunction)selectedCompare;
    }

    private int DrawByteControl(string label, ref bool foldoutState, int currentValue)
    {
        GUILayout.BeginHorizontal();
        foldoutState = EditorGUILayout.Foldout(foldoutState, $"{label}:");
        GUILayout.Space(100);
        int sliderValue = EditorGUILayout.IntSlider(GUIContent.none, currentValue, ByteMin, ByteMax);
        GUILayout.EndHorizontal();

        if (!foldoutState)
        {
            return sliderValue;
        }

        GUILayout.BeginHorizontal();
        GUILayout.Label($"{label} Bits:", GUILayout.Width(100));
        GUILayout.Space(60);
        int checkboxValue = 0;
        for (int i = 7; i >= 0; i--)
        {
            bool bit = ((currentValue >> i) & 1) == 1;
            bool newBit = GUILayout.Toggle(bit, GUIContent.none, GUILayout.Width(18));
            if (newBit)
            {
                checkboxValue |= 1 << i;
            }
        }
        GUILayout.EndHorizontal();

        if (sliderValue != currentValue)
        {
            return sliderValue;
        }

        return checkboxValue != currentValue ? checkboxValue : currentValue;
    }

    private static GUIStyle CreateBitStyle()
    {
        GUIStyle bitStyle = new GUIStyle(EditorStyles.label)
        {
            font = EditorStyles.miniLabel.font,
            alignment = TextAnchor.MiddleCenter,
            fixedWidth = 14,
            margin = new RectOffset(0, 0, 0, 0),
            padding = new RectOffset(0, 0, 0, 0)
        };

        return bitStyle;
    }

    private void DrawBitButtonRow(string label, ref int value, GUIStyle baseStyle, System.Func<int, Color> colorFunc = null, Color? overrideColor = null)
    {
        GUILayout.BeginHorizontal();
        GUILayout.Label(label, GUILayout.Width(LabelColumnWidth), GUILayout.Height(rowHeight));

        // Clone once per row to avoid per-bit allocations and color bleed across rows.
        GUIStyle bitStyle = new GUIStyle(baseStyle);

        for (int i = 7; i >= 0; i--)
        {
            bool bit = ((value >> i) & 1) == 1;
            if (overrideColor.HasValue)
            {
                ApplyColorToAllStates(bitStyle, overrideColor.Value);
            }
            else if (colorFunc != null)
            {
                ApplyColorToAllStates(bitStyle, colorFunc(i));
            }
            Rect bitRect = GUILayoutUtility.GetRect(new GUIContent(bit ? "1" : "0"), bitStyle, GUILayout.Width(14), GUILayout.Height(rowHeight));
            if (GUI.Button(bitRect, bit ? "1" : "0", bitStyle))
            {
                value ^= 1 << i;
            }
        }
        GUILayout.Space(ColumnGap);
        GUILayout.Label(value.ToString(), GUILayout.Width(DecimalColumnWidth), GUILayout.Height(rowHeight));
        GUILayout.EndHorizontal();
    }

    private void DrawBitLabelRow(string label, int value, GUIStyle bitStyle)
    {
        GUILayout.BeginHorizontal();
        GUILayout.Label(label, GUILayout.Width(LabelColumnWidth), GUILayout.Height(rowHeight));
        for (int i = 7; i >= 0; i--)
        {
            bool bit = ((value >> i) & 1) == 1;
            GUILayout.Label(bit ? "1" : "0", bitStyle, GUILayout.Width(14), GUILayout.Height(rowHeight));
        }
        GUILayout.Space(ColumnGap);
        GUILayout.Label(value.ToString(), GUILayout.Width(DecimalColumnWidth), GUILayout.Height(rowHeight));
        GUILayout.EndHorizontal();
    }

    private static void ApplyColorToAllStates(GUIStyle style, Color color)
    {
        style.normal.textColor = color;
        style.hover.textColor = Color.white;
        style.active.textColor = color;
        style.focused.textColor = color;
    }

    private static bool EvaluateStencilCompare(StencilCompareFunction compareFunction, int stencilValue, int refValue)
    {
        switch (compareFunction)
        {
            case StencilCompareFunction.Disabled:
                return true;
            case StencilCompareFunction.Never:
                return false;
            case StencilCompareFunction.Less:
                return stencilValue > refValue;
            case StencilCompareFunction.Equal:
                return stencilValue == refValue;
            case StencilCompareFunction.LessEqual:
                return stencilValue >= refValue;
            case StencilCompareFunction.Greater:
                return stencilValue < refValue;
            case StencilCompareFunction.NotEqual:
                return stencilValue != refValue;
            case StencilCompareFunction.GreaterEqual:
                return stencilValue <= refValue;
            case StencilCompareFunction.Always:
                return true;
            default:
                return false;
        }
    }

    private static int ApplyStencilOp(StencilOp op, int currentValue, int referenceValue)
    {
        switch (op)
        {
            case StencilOp.Keep:
                return currentValue;
            case StencilOp.Zero:
                return 0;
            case StencilOp.Replace:
                return referenceValue;
            case StencilOp.IncrementSaturate:
                return Mathf.Min(currentValue + 1, ByteMax);
            case StencilOp.DecrementSaturate:
                return Mathf.Max(currentValue - 1, ByteMin);
            case StencilOp.Invert:
                return (~currentValue) & 0xFF;
            case StencilOp.IncrementWrap:
                return (currentValue + 1) & 0xFF;
            case StencilOp.DecrementWrap:
                return currentValue == 0 ? ByteMax : currentValue - 1;
            default:
                return currentValue;
        }
    }
}
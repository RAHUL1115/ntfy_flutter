(() => {
  const MD_C = {
    surface: "#f4fbf8",
    surfaceVariant: "#dae5e1",
    inverseOnSurface: "#ecf2ef",
    secondaryContainer: "#cde8e1",
    primaryFixedDim: "#83d5c6",
    onSurface: "#171d1b",
    onSurfaceVar: "#49454f",
    onPrimaryContainer: "#00201c",
    primary: "#006a60",
    frameBorder: "rgba(116,119,117,0.5)"
  };
  function AndroidStatusBar({ dark = false }) {
    const c = dark ? "#fff" : MD_C.onSurface;
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: 40,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "0 16px",
      position: "relative",
      fontFamily: "Roboto, system-ui, sans-serif"
    } }, /* @__PURE__ */ React.createElement("div", { style: { width: 128, display: "flex", alignItems: "center", gap: 8 } }, /* @__PURE__ */ React.createElement("span", { style: { fontSize: 14, fontWeight: 400, letterSpacing: 0.25, lineHeight: "20px", color: c } }, "9:30")), /* @__PURE__ */ React.createElement("div", { style: {
      position: "absolute",
      left: "50%",
      top: 8,
      transform: "translateX(-50%)",
      width: 24,
      height: 24,
      borderRadius: 100,
      background: "#2e2e2e"
    } }), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", alignItems: "center" } }, /* @__PURE__ */ React.createElement("div", { style: { display: "flex", paddingRight: 2 } }, /* @__PURE__ */ React.createElement("svg", { width: "16", height: "16", viewBox: "0 0 16 16", style: { marginRight: -2 } }, /* @__PURE__ */ React.createElement("path", { d: "M8 13.3L.67 5.97a10.37 10.37 0 0114.66 0L8 13.3z", fill: c })), /* @__PURE__ */ React.createElement("svg", { width: "16", height: "16", viewBox: "0 0 16 16", style: { marginRight: -2 } }, /* @__PURE__ */ React.createElement("path", { d: "M14.67 14.67V1.33L1.33 14.67h13.34z", fill: c }))), /* @__PURE__ */ React.createElement("svg", { width: "16", height: "16", viewBox: "0 0 16 16" }, /* @__PURE__ */ React.createElement("rect", { x: "3.75", y: "2", width: "8.5", height: "13", rx: "1.5", fill: c }), /* @__PURE__ */ React.createElement("rect", { x: "5.5", y: "0.9", width: "5", height: "2", rx: "0.5", fill: c }))));
  }
  function AndroidAppBar({ title = "Title", large = false }) {
    const iconDot = /* @__PURE__ */ React.createElement("div", { style: {
      width: 48,
      height: 48,
      display: "flex",
      alignItems: "center",
      justifyContent: "center"
    } }, /* @__PURE__ */ React.createElement("div", { style: { width: 22, height: 22, borderRadius: "50%", background: MD_C.onSurfaceVar, opacity: 0.3 } }));
    return /* @__PURE__ */ React.createElement("div", { style: { background: MD_C.surface, padding: "4px 4px 0" } }, /* @__PURE__ */ React.createElement("div", { style: { height: 56, display: "flex", alignItems: "center", gap: 4 } }, iconDot, !large && /* @__PURE__ */ React.createElement("span", { style: {
      flex: 1,
      fontSize: 22,
      fontWeight: 400,
      color: MD_C.onSurface,
      fontFamily: "Roboto, system-ui, sans-serif"
    } }, title), large && /* @__PURE__ */ React.createElement("div", { style: { flex: 1 } }), iconDot), large && /* @__PURE__ */ React.createElement("div", { style: {
      padding: "16px 16px 20px",
      fontSize: 28,
      fontWeight: 400,
      color: MD_C.onSurface,
      fontFamily: "Roboto, system-ui, sans-serif"
    } }, title));
  }
  function AndroidListItem({ headline, supporting, leading }) {
    return /* @__PURE__ */ React.createElement("div", { style: {
      display: "flex",
      alignItems: "center",
      gap: 16,
      padding: "12px 16px",
      minHeight: 56,
      boxSizing: "border-box",
      fontFamily: "Roboto, system-ui, sans-serif"
    } }, leading && /* @__PURE__ */ React.createElement("div", { style: {
      width: 40,
      height: 40,
      borderRadius: "50%",
      background: MD_C.primary,
      color: "#fff",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 18,
      fontWeight: 500,
      flexShrink: 0
    } }, leading), /* @__PURE__ */ React.createElement("div", { style: { flex: 1, minWidth: 0 } }, /* @__PURE__ */ React.createElement("div", { style: { fontSize: 16, color: MD_C.onSurface, lineHeight: "24px" } }, headline), supporting && /* @__PURE__ */ React.createElement("div", { style: { fontSize: 14, color: MD_C.onSurfaceVar, lineHeight: "20px" } }, supporting)));
  }
  function AndroidNavBar({ dark = false }) {
    return /* @__PURE__ */ React.createElement("div", { style: {
      height: 24,
      display: "flex",
      alignItems: "center",
      justifyContent: "center"
    } }, /* @__PURE__ */ React.createElement("div", { style: {
      width: 108,
      height: 4,
      borderRadius: 2,
      background: dark ? "#fff" : MD_C.onSurface,
      opacity: 0.4
    } }));
  }
  function AndroidDevice({
    children,
    width = 412,
    height = 892,
    dark = false,
    title,
    large = false,
    keyboard = false
  }) {
    return (
      // data-om-starter: inert presence marker — Claude Design's starter-usage
      // probe reads it; it renders nothing. Keep it on this root element.
      /* @__PURE__ */ React.createElement("div", { "data-om-starter": "android-frame", style: {
        width,
        height,
        borderRadius: 18,
        overflow: "hidden",
        background: dark ? "#1d1b20" : MD_C.surface,
        border: `8px solid ${MD_C.frameBorder}`,
        boxShadow: "0 30px 80px rgba(0,0,0,0.25)",
        display: "flex",
        flexDirection: "column",
        boxSizing: "border-box"
      } }, /* @__PURE__ */ React.createElement(AndroidStatusBar, { dark }), title !== void 0 && /* @__PURE__ */ React.createElement(AndroidAppBar, { title, large }), /* @__PURE__ */ React.createElement("div", { style: { flex: 1, overflow: "auto" } }, children), keyboard && /* @__PURE__ */ React.createElement(AndroidKeyboard, null), /* @__PURE__ */ React.createElement(AndroidNavBar, { dark }))
    );
  }
  function AndroidKeyboard() {
    let _k = 0;
    const key = (l, { flex = 1, bg = MD_C.surface, r = 6, minW, fs = 21 } = {}) => /* @__PURE__ */ React.createElement("div", { key: _k++, style: {
      height: 46,
      borderRadius: r,
      flex,
      minWidth: minW,
      background: bg,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontFamily: "Roboto, system-ui",
      fontSize: fs,
      color: MD_C.onPrimaryContainer
    } }, l);
    const row = (keys, style = {}) => /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6, justifyContent: "center", ...style } }, keys.map((l) => key(l)));
    return /* @__PURE__ */ React.createElement("div", { style: {
      background: MD_C.inverseOnSurface,
      padding: "0 8px 8px",
      display: "flex",
      flexDirection: "column",
      gap: 4
    } }, /* @__PURE__ */ React.createElement("div", { style: { height: 44 } }), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", flexDirection: "column", gap: 12 } }, row(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]), row(["a", "s", "d", "f", "g", "h", "j", "k", "l"], { padding: "0 20px" }), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, key("", { bg: MD_C.surfaceVariant }), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6, flex: 7, minWidth: 274 } }, ["z", "x", "c", "v", "b", "n", "m"].map((l) => key(l))), key("", { bg: MD_C.surfaceVariant })), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", gap: 6 } }, key("?123", { bg: MD_C.secondaryContainer, r: 100, minW: 58, fs: 14 }), key(",", { bg: MD_C.surfaceVariant }), key("", { flex: 3, minW: 154 }), key(".", { bg: MD_C.surfaceVariant }), key("", { bg: MD_C.primaryFixedDim, r: 100, minW: 58 }))));
  }
  Object.assign(window, {
    AndroidDevice,
    AndroidStatusBar,
    AndroidAppBar,
    AndroidListItem,
    AndroidNavBar,
    AndroidKeyboard
  });
})();

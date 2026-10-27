/* AYOL360 CRM — mobile-first sales CRM on Supabase */
(function () {
  "use strict";

  var STAGES = [
    ["new", "Yangi lid"],
    ["no_answer", "Ko‘tarmadi"],
    ["thinking", "O‘ylab ko‘ryapti"],
    ["card", "Kartaga to‘lov"],
    ["installment", "Uzum/Paylater"],
    ["contract", "Shartnoma"],
    ["refused", "Atkaz"]
  ];
  var STAGE_NAME = {};
  STAGES.forEach(function (s) { STAGE_NAME[s[0]] = s[1]; });
  var FREE = "_free";            // former "Taqsimlanmagan" chip; only kept to migrate saved UI state
  var NO_MGR = "_none";          // manager filter: leads without a manager (they are always "Yangi lid")
  var RECYCLE_STAGES = ["no_answer", "thinking"];   // pre-checked on the "Qayta ishlash" tab
  var BACK_TO_POOL = { stage: "new", manager_id: null, next_call_at: null };
  var XLSX_URL = "https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js";
  var PAGE = 50;
  var LOGIN_DOMAIN = "@ayol360.uz";

  var cfg = window.AYOL360_CONFIG || {};
  // Phones with a wrong clock see every token as already expired and refresh in a loop until
  // Supabase rate-limits them and the session ends. Store expiry relative to THIS device's clock.
  var clockSkew = 0;
  function jwtPayload(t) {
    var b = t.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    while (b.length % 4) b += "=";
    return JSON.parse(atob(b));
  }
  var authStorage = {
    getItem: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    setItem: function (k, v) {
      try {
        var o = JSON.parse(v);
        if (o && o.access_token) {
          var p = jwtPayload(o.access_token);
          var now = Math.floor(Date.now() / 1000);
          if (p.iat && p.exp) { clockSkew = now - p.iat; o.expires_at = now + (p.exp - p.iat); v = JSON.stringify(o); }
        }
      } catch (e) { /* keep value as is */ }
      try { localStorage.setItem(k, v); } catch (e) { /* private mode */ }
    },
    removeItem: function (k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } }
  };
  var sb = window.supabase.createClient(cfg.url, cfg.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: "ayol360-crm-auth", storage: authStorage }
  });

  var me = null;                 // profile row
  var staff = [];                // profiles visible to me
  var offices = [];
  var ui = {};                   // persisted UI state
  var list = { rows: [], done: false, loading: false, selecting: false, selected: {} };
  var counts = {};
  var restoreScroll = null;
  var app = document.getElementById("app");

  // ---------------- helpers ----------------
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v == null || v === false) return;
      if (k === "class") el.className = v;
      else if (k === "text") el.textContent = v;
      else if (k.slice(0, 2) === "on") el.addEventListener(k.slice(2), v);
      else if (k === "value") el.value = v;
      else if (k === "checked") el.checked = !!v;
      else el.setAttribute(k, v === true ? "" : v);
    });
    for (var i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { add(el, x); }); return; }
    el.appendChild(typeof c === "object" ? c : document.createTextNode(String(c)));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }
  var toastTimer;
  function toast(msg) {
    var t = document.getElementById("toast");
    t.textContent = msg; t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, 2600);
  }
  function errText(e) {
    var m = (e && (e.message || e.error_description)) || String(e);
    if (/Invalid login/i.test(m)) return "Login yoki parol noto‘g‘ri";
    if (/already registered|already exists/i.test(m)) return "Bu login band";
    if (/Password should be/i.test(m)) return "Parol kamida 6 belgidan iborat bo‘lsin";
    if (/Failed to fetch|NetworkError/i.test(m)) return "Internet aloqasini tekshiring";
    return m;
  }
  function fail(e) { console.error(e); toast(errText(e)); }
  function fmtDate(iso, withTime) {
    if (!iso) return "";
    var d = new Date(iso);
    var p = function (n) { return (n < 10 ? "0" : "") + n; };
    var s = p(d.getDate()) + "." + p(d.getMonth() + 1);
    if (d.getFullYear() !== new Date().getFullYear()) s += "." + d.getFullYear();
    return withTime === false ? s : s + " " + p(d.getHours()) + ":" + p(d.getMinutes());
  }
  function toLocalInput(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().slice(0, 16);
  }
  function money(n) { return n == null ? "" : String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " "); }
  function staffName(id) {
    for (var i = 0; i < staff.length; i++) if (staff[i].id === id) return staff[i].full_name || staff[i].email;
    return "";
  }
  function officeName(id) {
    for (var i = 0; i < offices.length; i++) if (offices[i].id === id) return offices[i].name;
    return "Ofis " + id;
  }
  function isAdmin() { return me && (me.role === "admin" || me.role === "super"); }
  // "Toshkent — admin: Dilnoza": leads moved to a branch land in its admin's "Yangi lid" without a manager
  function officeWithAdmin(id) {
    var names = staff.filter(function (s) { return s.role === "admin" && s.active && s.office_id === id; })
      .map(function (s) { return s.full_name || s.email; });
    return officeName(id) + " — " + (names.length ? "admin: " + names.join(", ") : "admini yo‘q");
  }
  function activeOffice() { return me.role === "super" ? (ui.office || null) : me.office_id; }
  function managersOf(officeId) {
    return staff.filter(function (s) {
      return s.role === "manager" && s.active && (officeId == null || s.office_id === officeId);
    });
  }

  // ---------------- persisted UI state ----------------
  function stateKey() { return "ayol360.ui." + (me ? me.id : "x"); }
  function loadUi() {
    try { ui = JSON.parse(localStorage.getItem(stateKey()) || "{}") || {}; } catch (e) { ui = {}; }
    if (!ui.tab) ui.tab = "leads";
    if (!ui.stage || ui.stage === FREE) ui.stage = "new";
    if (!isAdmin() && ui.mgr) ui.mgr = "";
    if (!isAdmin() && ui.tab !== "leads" && ui.tab !== "stats") ui.tab = "leads";
  }
  var saveTimer;
  function saveUi() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      try { localStorage.setItem(stateKey(), JSON.stringify(ui)); } catch (e) { /* private mode */ }
    }, 120);
  }
  window.addEventListener("scroll", function () {
    if (ui.tab === "leads" && !document.querySelector(".sheet")) { ui.scrollY = window.scrollY; saveUi(); }
  }, { passive: true });

  // ---------------- boot / auth ----------------
  async function boot() {
    if (!cfg.url || !cfg.anonKey) { clear(app).appendChild(h("div", { class: "boot", text: "config.js sozlanmagan" })); return; }
    var res = await sb.auth.getSession();
    if (!res.data.session) return renderLogin();
    await enter();
  }

  async function enter() {
    var sess = (await sb.auth.getSession()).data.session;
    var uid = sess && sess.user;
    if (!uid) return renderLogin();
    var p = await sb.from("profiles").select("*").eq("id", uid.id).single();
    if (p.error || !p.data || !p.data.active || !p.data.role) {
      await sb.auth.signOut({ scope: "local" });
      return renderLogin(p.error ? "Ma’lumotni olib bo‘lmadi: " + errText(p.error) : "Akkauntingiz hali faollashtirilmagan. Administratorga murojaat qiling.");
    }
    me = p.data;
    if (Math.abs(clockSkew) > 300) setTimeout(function () { toast("Telefon soati noto‘g‘ri. Sozlamalarda avtomatik vaqtni yoqing."); }, 800);
    loadUi();
    var o = await sb.from("offices").select("*").order("id");
    offices = o.data || [];
    await loadStaff();
    // a branch used by staff but missing from (or hidden in) "offices" must still be selectable
    staff.concat([me]).forEach(function (s) {
      if (s.office_id != null && !offices.some(function (x) { return x.id === s.office_id; })) offices.push({ id: s.office_id, name: "Ofis " + s.office_id });
    });
    offices.sort(function (a, b) { return a.id - b.id; });
    renderShell();
  }

  async function loadStaff() {
    if (me.role === "manager") { staff = [me]; return; }
    var r = await sb.from("profiles").select("*").order("full_name");
    staff = r.data || [];
  }

  function renderLogin(msg) {
    clear(app);
    var err = h("div", { class: "err", text: msg || "" });
    var login = h("input", { autocomplete: "username", autocapitalize: "none", placeholder: "login yoki email", required: true });
    var pass = h("input", { type: "password", autocomplete: "current-password", placeholder: "parol", required: true });
    var btn = h("button", { class: "btn block", type: "submit", text: "Kirish" });
    var form = h("form", {
      onsubmit: async function (e) {
        e.preventDefault();
        err.textContent = ""; btn.disabled = true;
        var email = login.value.trim().toLowerCase();
        if (email.indexOf("@") < 0) email += LOGIN_DOMAIN;
        var r = await sb.auth.signInWithPassword({ email: email, password: pass.value });
        btn.disabled = false;
        if (r.error) { err.textContent = errText(r.error); return; }
        await enter();
      }
    },
      h("div", { class: "logo" }, "AYOL360", h("small", { text: "CRM" })),
      h("p", { text: "Sotuv bo‘limi uchun ish oynasi" }),
      h("label", { text: "Login" }), login,
      h("label", { text: "Parol" }), pass,
      btn, err);
    app.appendChild(h("div", { class: "login" }, form));
  }

  // ---------------- shell ----------------
  var mainEl, topEl;
  function tabsFor() {
    var t = [["leads", "Lidlar"]];
    if (isAdmin()) t.push(["recycle", "Qayta ishlash"]);
    if (me.role === "super" && offices.length > 1) t.push(["transfer", "O‘tkazish"]);
    if (isAdmin()) t.push(["import", "Yuklash"], ["staff", "Xodimlar"]);
    t.push(["stats", "Statistika"]);
    return t;
  }

  function renderShell() {
    clear(app);
    var officeSel = null;
    if (me.role === "super") {
      officeSel = h("select", {
        onchange: function () {
          ui.office = officeSel.value ? Number(officeSel.value) : null;
          ui.scrollY = 0; ui.mgr = ""; saveUi(); renderTab(true);
        }
      }, h("option", { value: "", text: "Barcha ofislar" }),
        offices.map(function (o) { return h("option", { value: o.id, text: o.name }); }));
      officeSel.value = ui.office || "";
    }
    var tabs = h("nav", { class: "tabs" }, tabsFor().map(function (t) {
      return h("button", {
        class: ui.tab === t[0] ? "on" : "", "data-tab": t[0],
        onclick: function () { ui.tab = t[0]; ui.scrollY = 0; saveUi(); renderShell(); }
      }, t[1]);
    }));
    topEl = h("header", { class: "top" },
      h("div", { class: "top-row" },
        h("div", { class: "logo", text: "AYOL360" }),
        officeSel,
        h("div", { class: "who" }, me.full_name || me.email, h("br"),
          h("span", { text: me.role === "super" ? "Bosh admin" : me.role === "admin" ? officeName(me.office_id) + " admini" : officeName(me.office_id) })),
        h("button", { class: "icon-btn", style: "padding:0 10px;font-size:14px;font-weight:600", onclick: logout, text: "Chiqish" })),
      tabs);
    mainEl = h("main");
    app.appendChild(topEl);
    app.appendChild(mainEl);
    requestAnimationFrame(function () {
      document.documentElement.style.setProperty("--top-h", topEl.offsetHeight + "px");
    });
    renderTab(false);
  }

  function resetState() {
    me = null; staff = []; ui = {}; counts = {};
    list = { rows: [], done: false, loading: false, selecting: false, selected: {} };
    var s = document.querySelector(".sheet"); if (s) s.remove();
    var b = document.querySelector(".bar"); if (b) b.remove();
    document.body.style.overflow = "";
  }

  async function logout() {
    // "local": only this device logs out; other devices of the same account stay signed in
    await sb.auth.signOut({ scope: "local" });
    resetState();
    renderLogin();
  }

  function renderTab(reset) {
    var bar = document.querySelector(".bar"); if (bar) bar.remove();
    clear(mainEl);
    if (ui.tab === "recycle" && isAdmin()) return renderRecycle();
    if (ui.tab === "transfer" && me.role === "super") return renderTransfer();
    if (ui.tab === "import" && isAdmin()) return renderImport();
    if (ui.tab === "staff" && isAdmin()) return renderStaff();
    if (ui.tab === "stats") return renderStats();
    ui.tab = "leads";
    renderLeads(reset);
  }

  // ---------------- leads ----------------
  var listEl, chipsEl, searchEl, mgrSel, moreBtn;

  function chipKeys() { return STAGES.map(function (s) { return s[0]; }); }
  function chipLabel(k) { return STAGE_NAME[k]; }

  function baseQuery(q, forCount) {
    var off = activeOffice();
    if (off != null) q = q.eq("office_id", off);
    if (isAdmin() && ui.mgr) q = ui.mgr === NO_MGR ? q.is("manager_id", null) : q.eq("manager_id", ui.mgr);
    var s = (ui.q || "").trim();
    if (s) {
      var safe = s.replace(/[,()%*\\]/g, " ").trim();
      var digits = s.replace(/\D/g, "");
      var parts = ["name.ilike.%" + safe + "%"];
      if (digits.length >= 3) parts.push("phone.ilike.%" + digits + "%");
      q = q.or(parts.join(","));
    }
    return q;
  }
  function stageFilter(q, k) { return q.eq("stage", k); }

  function renderLeads(reset) {
    if (reset) { list.rows = []; list.done = false; list.selected = {}; }
    chipsEl = h("div", { class: "stages" });
    searchEl = h("input", {
      type: "search", placeholder: "Ism yoki telefon bo‘yicha qidirish", value: ui.q || "",
      oninput: debounce(function () { ui.q = searchEl.value; ui.scrollY = 0; saveUi(); reloadLeads(); }, 350)
    });
    var tools = [searchEl];
    if (isAdmin()) {
      mgrSel = h("select", {
        onchange: function () { ui.mgr = mgrSel.value; ui.scrollY = 0; saveUi(); reloadLeads(); }
      }, h("option", { value: "", text: "Barcha menejerlar" }),
        h("option", { value: NO_MGR, text: "Menejersiz (taqsimlanmagan)" }),
        managersOf(activeOffice()).map(function (m) { return h("option", { value: m.id, text: m.full_name || m.email }); }));
      mgrSel.value = ui.mgr || "";
      if (mgrSel.value !== (ui.mgr || "")) { ui.mgr = ""; }
      tools.push(mgrSel);
      tools.push(h("button", {
        class: "btn line", text: list.selecting ? "Bekor" : "Tanlash",
        onclick: function () { list.selecting = !list.selecting; list.selected = {}; renderTab(false); }
      }));
    }
    listEl = h("div", { class: "list" });
    moreBtn = h("button", { class: "btn ghost more", text: "Yana ko‘rsatish", hidden: true, onclick: loadMore });
    mainEl.appendChild(chipsEl);
    mainEl.appendChild(h("div", { class: "toolbar" }, tools));
    mainEl.appendChild(listEl);
    mainEl.appendChild(moreBtn);
    renderChips();
    restoreScroll = reset ? 0 : (ui.scrollY || 0);
    reloadLeads(true);
    if (ui.lead) openLead(ui.lead, true);
  }

  function renderChips() {
    clear(chipsEl);
    chipKeys().forEach(function (k) {
      var b = h("button", {
        class: "stage" + (ui.stage === k ? " on" : ""),
        onclick: function () {
          if (ui.stage === k) return;
          ui.stage = k; ui.scrollY = 0; list.selected = {}; saveUi();
          renderChips(); reloadLeads();
          window.scrollTo(0, 0);
        }
      }, chipLabel(k), h("b", { text: counts[k] == null ? "…" : counts[k] }));
      chipsEl.appendChild(b);
      if (ui.stage === k) setTimeout(function () { b.scrollIntoView({ inline: "center", block: "nearest" }); }, 0);
    });
  }

  async function loadCounts() {
    var keys = chipKeys();
    var res = await Promise.all(keys.map(function (k) {
      return stageFilter(baseQuery(sb.from("leads").select("id", { count: "exact", head: true })), k);
    }));
    res.forEach(function (r, i) { counts[keys[i]] = r.error ? "!" : r.count; });
    if (chipsEl && chipsEl.isConnected) renderChips();
  }

  async function fetchPage(from, to) {
    var q = baseQuery(sb.from("leads").select("id,name,phone,stage,next_call_at,manager_id,office_id,updated_at,created_at"));
    if (!(ui.q || "").trim()) q = stageFilter(q, ui.stage);
    if (ui.stage === "new") q = q.order("created_at", { ascending: false });
    else q = q.order("next_call_at", { ascending: true, nullsFirst: false }).order("updated_at", { ascending: false });
    return q.range(from, to);
  }

  async function reloadLeads(keepScroll) {
    loadCounts();
    list.loading = true;
    var want = keepScroll && list.rows.length ? Math.max(PAGE, list.rows.length) : (keepScroll && restoreScroll ? PAGE * 3 : PAGE);
    var r = await fetchPage(0, want - 1);
    list.loading = false;
    if (r.error) {
      fail(r.error);
      if (listEl && listEl.isConnected) clear(listEl).appendChild(h("div", { class: "empty", text: "Lidlarni yuklab bo‘lmadi: " + errText(r.error) }));
      return;
    }
    list.rows = r.data;
    list.done = r.data.length < want;
    drawList();
    if (restoreScroll != null) {
      var y = restoreScroll; restoreScroll = null;
      requestAnimationFrame(function () { window.scrollTo(0, y); });
    }
  }

  async function loadMore() {
    if (list.loading || list.done) return;
    list.loading = true; moreBtn.disabled = true;
    var r = await fetchPage(list.rows.length, list.rows.length + PAGE - 1);
    list.loading = false; moreBtn.disabled = false;
    if (r.error) return fail(r.error);
    list.rows = list.rows.concat(r.data);
    list.done = r.data.length < PAGE;
    drawList();
  }

  function drawList() {
    if (!listEl || !listEl.isConnected) return;
    clear(listEl);
    var searching = !!(ui.q || "").trim();
    if (!list.rows.length) {
      listEl.appendChild(h("div", { class: "empty", text: searching ? "Hech narsa topilmadi" : "Bu bosqichda lid yo‘q" }));
    }
    var now = Date.now();
    list.rows.forEach(function (r) {
      var meta = [];
      if (r.next_call_at) {
        var t = new Date(r.next_call_at).getTime();
        var cls = t < now ? "late" : (t - now < 3 * 3600e3 ? "soon" : "");
        meta.push(h("span", { class: cls, text: "📅 " + fmtDate(r.next_call_at) }));
      }
      if (searching) meta.push(STAGE_NAME[r.stage]);
      if (isAdmin()) meta.push(r.manager_id ? staffName(r.manager_id) : "menejersiz");
      if (me.role === "super" && activeOffice() == null) meta.push(officeName(r.office_id));
      meta = meta.reduce(function (acc, m, i) { if (i) acc.push(" · "); acc.push(m); return acc; }, []);
      var check = null;
      if (list.selecting) {
        check = h("input", {
          type: "checkbox", checked: !!list.selected[r.id],
          onclick: function (e) { e.stopPropagation(); },
          onchange: function () { if (check.checked) list.selected[r.id] = true; else delete list.selected[r.id]; drawBar(); }
        });
      }
      listEl.appendChild(h("div", {
        class: "lead",
        onclick: function () {
          if (list.selecting) { check.checked = !check.checked; check.dispatchEvent(new Event("change")); return; }
          openLead(r.id);
        }
      },
        check,
        h("div", { class: "main" },
          h("div", { class: "name", text: r.name || "Ismsiz" }),
          h("div", { class: "phone", text: r.phone }),
          meta.length ? h("div", { class: "meta" }, meta) : null),
        list.selecting ? null : h("a", {
          class: "call", href: "tel:" + r.phone, "aria-label": "Qo‘ng‘iroq qilish",
          onclick: function (e) { e.stopPropagation(); }
        }, "📞")));
    });
    moreBtn.hidden = list.done || searching && list.rows.length < PAGE;
    drawBar();
  }

  function drawBar() {
    var old = document.querySelector(".bar"); if (old) old.remove();
    if (mainEl) mainEl.style.paddingBottom = "";
    if (!list.selecting) return;
    var n = Object.keys(list.selected).length;
    var bar = document.body.appendChild(h("div", { class: "bar", style: "flex-wrap:wrap" },
      h("button", {
        class: "btn line", text: "Hammasi",
        onclick: function () { list.rows.forEach(function (r) { list.selected[r.id] = true; }); drawList(); }
      }),
      h("div", { class: "grow", text: n + " ta tanlandi" }),
      ui.mgr === NO_MGR ? null : h("button", { class: "btn line", text: "Qaytarish", disabled: !n, onclick: returnSelected }),
      me.role === "super" && offices.length > 1 ? h("button", { class: "btn line", text: "Filialga", disabled: !n, onclick: openMoveOffice }) : null,
      h("button", { class: "btn", text: "Menejerga berish", disabled: !n, onclick: openDistribute })));
    // the bar may wrap to two rows on phones: keep the last lead visible above it
    if (mainEl) mainEl.style.paddingBottom = (bar.offsetHeight + 16) + "px";
  }

  // Super admin: move selected leads to another branch as new leads without a manager; note and history are kept.
  function openMoveOffice() {
    var ids = Object.keys(list.selected).map(Number);
    var from = {};
    list.rows.forEach(function (r) { if (list.selected[r.id]) from[r.office_id] = true; });
    var offSel = h("select", null, offices.map(function (o) { return h("option", { value: o.id, text: officeWithAdmin(o.id) }); }));
    var others = offices.filter(function (o) { return !from[o.id]; });
    if (others.length) offSel.value = others[0].id;
    var err = h("div", { class: "err" });
    modal(function (close) {
      return [
        h("h2", { text: ids.length + " ta lidni boshqa filialga o‘tkazish" }),
        h("p", { class: "hint", text: "Lidlar menejerdan olinadi va tanlangan filial adminining \"Yangi lid\" bo‘limiga menejersiz tushadi. Admin ularni o‘z menejerlariga taqsimlaydi. Izoh va tarix saqlanadi." }),
        h("label", { text: "Qaysi filial adminiga" }), offSel,
        err,
        h("div", { class: "row" },
          h("button", { class: "btn line", text: "Bekor", onclick: close }),
          h("button", {
            class: "btn", text: "O‘tkazish",
            onclick: async function (e) {
              var to = Number(offSel.value);
              var move = ids.filter(function (id) {
                for (var i = 0; i < list.rows.length; i++) if (list.rows[i].id === id) return list.rows[i].office_id !== to;
                return true;
              });
              if (!move.length) { err.textContent = "Tanlangan lidlar allaqachon shu filialda"; return; }
              var fields = Object.assign({ office_id: to }, BACK_TO_POOL);
              e.target.disabled = true;
              var done = 0;
              for (var i = 0; i < move.length; i += 200) {
                var r = await sb.from("leads").update(fields).in("id", move.slice(i, i + 200)).select("id");
                if (r.error) { err.textContent = errText(r.error); e.target.disabled = false; return; }
                done += r.data.length;
              }
              close();
              toast(done + " ta lid " + officeName(to) + " filialiga o‘tkazildi");
              list.selecting = false; list.selected = {};
              renderTab(false);
            }
          }))
      ];
    });
  }

  // Selected leads go back to the admin as new leads without a manager; note and history are kept.
  function returnSelected() {
    var ids = Object.keys(list.selected).map(Number);
    var err = h("div", { class: "err" });
    modal(function (close) {
      return [
        h("h2", { text: ids.length + " ta lidni qaytarish" }),
        h("p", { class: "hint", text: "Tanlangan lidlar menejerdan olinadi va \"Yangi lid\" bo‘limiga menejersiz qaytadi. Izoh va tarix saqlanadi." }),
        err,
        h("div", { class: "row" },
          h("button", { class: "btn line", text: "Bekor", onclick: close }),
          h("button", {
            class: "btn", text: "Qaytarish",
            onclick: async function (e) {
              e.target.disabled = true;
              var done = 0;
              for (var i = 0; i < ids.length; i += 200) {
                var r = await sb.from("leads").update(BACK_TO_POOL).in("id", ids.slice(i, i + 200)).select("id");
                if (r.error) { err.textContent = errText(r.error); e.target.disabled = false; return; }
                done += r.data.length;
              }
              close();
              toast(done + " ta lid qaytarildi");
              list.selecting = false; list.selected = {};
              renderTab(false);
            }
          }))
      ];
    });
  }

  function openDistribute() {
    var ids = Object.keys(list.selected).map(Number);
    var office = activeOffice();
    var rowsOffice = {};
    list.rows.forEach(function (r) { if (list.selected[r.id]) rowsOffice[r.office_id] = true; });
    var offs = Object.keys(rowsOffice);
    if (offs.length > 1) return toast("Bir martada faqat bitta ofis lidlarini taqsimlang");
    var off = office != null ? office : Number(offs[0]);
    var mgrs = managersOf(off);
    if (!mgrs.length) return toast("Bu ofisda faol menejer yo‘q");
    var boxes = mgrs.map(function (m) {
      var cb = h("input", { type: "checkbox", value: m.id });
      return { cb: cb, el: h("label", null, cb, m.full_name || m.email) };
    });
    var err = h("div", { class: "err" });
    modal(function (close) {
      return [
        h("h2", { text: ids.length + " ta lidni taqsimlash" }),
        h("p", { class: "hint", text: "Bir nechta menejer tanlasangiz, lidlar ular orasida navbat bilan teng bo‘linadi." }),
        h("div", { class: "picker" }, boxes.map(function (b) { return b.el; })),
        err,
        h("div", { class: "row" },
          h("button", { class: "btn line", text: "Bekor", onclick: close }),
          h("button", {
            class: "btn", text: "Berish",
            onclick: async function () {
              var chosen = boxes.filter(function (b) { return b.cb.checked; }).map(function (b) { return b.cb.value; });
              if (!chosen.length) { err.textContent = "Kamida bitta menejer tanlang"; return; }
              var r = await sb.rpc("distribute_leads", { p_leads: ids, p_managers: chosen });
              if (r.error) { err.textContent = errText(r.error); return; }
              close();
              toast(r.data + " ta lid taqsimlandi");
              list.selecting = false; list.selected = {};
              renderTab(false);
            }
          }))
      ];
    });
  }

  // ---------------- lead sheet ----------------
  async function openLead(id, restoring) {
    ui.lead = id; saveUi();
    if (!(history.state && history.state.lead === id)) history.pushState({ lead: id }, "");
    var r = await sb.from("leads").select("*").eq("id", id).maybeSingle();
    if (r.error || !r.data) { closeLead(true); if (r.error) fail(r.error); return; }
    drawSheet(r.data);
  }

  function closeLead(fromCode) {
    var s = document.querySelector(".sheet"); if (s) s.remove();
    document.body.style.overflow = "";
    if (ui.lead != null) { ui.lead = null; saveUi(); }
    if (fromCode !== "pop" && history.state && history.state.lead) history.back();
  }
  window.addEventListener("popstate", function () {
    if (document.querySelector(".sheet")) closeLead("pop");
  });

  function patchRow(lead) {
    for (var i = 0; i < list.rows.length; i++) {
      if (list.rows[i].id === lead.id) {
        var moved = !(ui.q || "").trim() && lead.stage !== ui.stage;
        if (ui.mgr === NO_MGR && lead.manager_id) moved = true;
        if (moved) list.rows.splice(i, 1); else list.rows[i] = Object.assign(list.rows[i], lead);
        break;
      }
    }
    drawList(); loadCounts();
  }

  async function save(lead, fields, okMsg) {
    var r = await sb.from("leads").update(fields).eq("id", lead.id).select().single();
    if (r.error) { fail(r.error); return null; }
    Object.assign(lead, r.data);
    patchRow(r.data);
    if (okMsg) toast(okMsg);
    return r.data;
  }

  function drawSheet(lead) {
    var old = document.querySelector(".sheet"); if (old) old.remove();
    document.body.style.overflow = "hidden";
    var histEl = h("ul", { class: "hist" });

    var stageGrid = h("div", { class: "stage-grid" });
    function drawStages() {
      clear(stageGrid);
      STAGES.forEach(function (s) {
        stageGrid.appendChild(h("button", {
          class: lead.stage === s[0] ? "on" : "",
          onclick: async function () {
            if (lead.stage === s[0]) return;
            var ok = await save(lead, { stage: s[0] }, "Bosqich: " + s[1]);
            if (ok) { drawStages(); loadHistory(); }
          }
        }, s[1]));
      });
    }
    drawStages();

    var nextInp = h("input", { type: "datetime-local", value: toLocalInput(lead.next_call_at) });
    function quick(label, fn) {
      return h("button", { class: "btn line", type: "button", text: label, onclick: function () { nextInp.value = toLocalInput(fn().toISOString()); } });
    }
    var amountInp = h("input", { type: "text", inputmode: "numeric", placeholder: "masalan 1 200 000", value: money(lead.amount) });
    var noteInp = h("textarea", { placeholder: "Mijoz haqida izoh", value: lead.note || "" });
    var commentInp = h("input", { placeholder: "Qo‘ng‘iroq natijasi yoki izoh…" });

    async function saveDetails() {
      var amt = amountInp.value.replace(/\D/g, "");
      await save(lead, {
        next_call_at: nextInp.value ? new Date(nextInp.value).toISOString() : null,
        amount: amt ? Number(amt) : null,
        note: noteInp.value
      }, "Saqlandi");
    }

    async function loadHistory() {
      var r = await sb.from("lead_events").select("*").eq("lead_id", lead.id).order("created_at", { ascending: false }).limit(50);
      clear(histEl);
      if (r.error) return fail(r.error);
      if (!r.data.length) histEl.appendChild(h("li", { class: "hint", text: "Hali tarix yo‘q" }));
      r.data.forEach(function (e) {
        var txt = e.kind === "stage" ? "Bosqich → " + (STAGE_NAME[e.body] || e.body)
          : e.kind === "assign" ? "Menejer → " + (e.body || "olib tashlandi")
          : e.body;
        histEl.appendChild(h("li", null, txt, h("small", { text: fmtDate(e.created_at) + (e.actor_id ? " · " + (staffName(e.actor_id) || "") : "") })));
      });
    }

    var adminBox = null;
    if (isAdmin()) {
      var mSel = h("select", null, h("option", { value: "", text: "— menejersiz —" }),
        managersOf(lead.office_id).map(function (m) { return h("option", { value: m.id, text: m.full_name || m.email }); }));
      mSel.value = lead.manager_id || "";
      var oSel = null;
      if (me.role === "super") {
        oSel = h("select", null, offices.map(function (o) { return h("option", { value: o.id, text: o.name }); }));
        oSel.value = lead.office_id;
      }
      adminBox = h("div", { class: "box" },
        h("h3", { text: "Boshqaruv" }),
        oSel ? [h("label", { text: "Ofis" }), oSel] : null,
        h("label", { text: "Menejer" }), mSel,
        h("div", { class: "row", style: "margin-top:12px" },
          h("button", {
            class: "btn ghost", text: "Saqlash",
            onclick: async function () {
              var f = { manager_id: mSel.value || null };
              if (oSel && Number(oSel.value) !== lead.office_id) { f.office_id = Number(oSel.value); f.manager_id = null; }
              // a lead without a manager is always a new lead, so the admin finds it under "Yangi lid"
              if (!f.manager_id && lead.manager_id && lead.stage !== "new") { f.stage = "new"; f.next_call_at = null; }
              var ok = await save(lead, f, "Saqlandi");
              if (ok) drawSheet(lead);
            }
          }),
          h("button", {
            class: "btn danger", text: "O‘chirish",
            onclick: function () {
              modal(function (close) {
                return [h("h2", { text: "Lidni o‘chirasizmi?" }),
                  h("p", { class: "hint", text: (lead.name || "") + " " + lead.phone + " butunlay o‘chiriladi." }),
                  h("div", { class: "row" },
                    h("button", { class: "btn line", text: "Yo‘q", onclick: close }),
                    h("button", {
                      class: "btn danger", text: "Ha, o‘chirish",
                      onclick: async function () {
                        var r = await sb.from("leads").delete().eq("id", lead.id);
                        if (r.error) return fail(r.error);
                        close(); closeLead();
                        list.rows = list.rows.filter(function (x) { return x.id !== lead.id; });
                        drawList(); loadCounts(); toast("O‘chirildi");
                      }
                    }))];
              });
            }
          })));
    }

    var sheet = h("div", { class: "sheet" },
      h("div", { class: "sheet-head" },
        h("button", { class: "icon-btn", "aria-label": "Orqaga", text: "←", onclick: function () { closeLead(); } }),
        h("div", { class: "title", text: lead.name || "Ismsiz" })),
      h("div", { class: "sheet-body" },
        h("div", { class: "box" },
          h("div", { class: "big-phone", text: lead.phone }),
          h("div", { class: "row" },
            h("a", { class: "btn", href: "tel:" + lead.phone, style: "text-decoration:none" }, "📞 Qo‘ng‘iroq"),
            h("button", {
              class: "btn ghost", text: "Nusxa olish",
              onclick: function () {
                (navigator.clipboard ? navigator.clipboard.writeText(lead.phone) : Promise.reject())
                  .then(function () { toast("Raqam nusxalandi"); }, function () { toast(lead.phone); });
              }
            })),
          h("p", { class: "hint", style: "margin:10px 0 0" },
            (lead.source ? lead.source + " · " : "") + "qo‘shilgan " + fmtDate(lead.created_at, false) +
            (isAdmin() ? " · " + (lead.manager_id ? staffName(lead.manager_id) : "menejersiz") : ""))),
        h("div", { class: "box" }, h("h3", { text: "Bosqich" }), stageGrid),
        h("div", { class: "box" },
          h("h3", { text: "Keyingi qo‘ng‘iroq" }),
          nextInp,
          h("div", { class: "row", style: "margin-top:8px" },
            quick("+1 soat", function () { return new Date(Date.now() + 3600e3); }),
            quick("Ertaga 10:00", function () { var d = new Date(); d.setDate(d.getDate() + 1); d.setHours(10, 0, 0, 0); return d; }),
            h("button", { class: "btn line", type: "button", text: "Tozalash", onclick: function () { nextInp.value = ""; } })),
          h("label", { text: "Summa (so‘m)" }), amountInp,
          h("label", { text: "Izoh" }), noteInp,
          h("button", { class: "btn block", text: "Saqlash", onclick: saveDetails })),
        h("div", { class: "box" },
          h("h3", { text: "Tarix" }),
          h("div", { class: "row", style: "margin-bottom:10px" },
            commentInp,
            h("button", {
              class: "btn", style: "flex:0 0 auto", text: "Qo‘shish",
              onclick: async function () {
                var t = commentInp.value.trim(); if (!t) return;
                var r = await sb.from("lead_events").insert({ lead_id: lead.id, kind: "comment", body: t });
                if (r.error) return fail(r.error);
                commentInp.value = ""; loadHistory();
              }
            })),
          histEl),
        adminBox));
    document.body.appendChild(sheet);
    loadHistory();
  }

  // ---------------- modal ----------------
  function modal(build) {
    var wrap;
    function close() { wrap.remove(); }
    var panel = h("div", { class: "panel" });
    wrap = h("div", { class: "modal", onclick: function (e) { if (e.target === wrap) close(); } }, panel);
    add(panel, build(close));
    document.body.appendChild(wrap);
  }

  // ---------------- recycle: managers' stalled leads back to the pool ----------------
  function renderRecycle() {
    var office = activeOffice();
    var stageBoxes = STAGES.filter(function (s) { return s[0] !== "new"; }).map(function (s) {
      var cb = h("input", { type: "checkbox", value: s[0], checked: RECYCLE_STAGES.indexOf(s[0]) >= 0, onchange: refresh });
      return { cb: cb, el: h("label", null, cb, s[1]) };
    });
    // all managers of the office, including switched-off ones: their leads must not get stuck
    var mgrs = staff.filter(function (s) { return s.role === "manager" && (office == null || s.office_id === office); });
    var mgrBoxes = [];
    var allCb = h("input", {
      type: "checkbox", checked: true,
      onchange: function () { mgrBoxes.forEach(function (b) { b.cb.checked = allCb.checked; }); refresh(); }
    });
    mgrBoxes = mgrs.map(function (m) {
      var cb = h("input", {
        type: "checkbox", value: m.id, checked: true,
        onchange: function () { allCb.checked = mgrBoxes.every(function (b) { return b.cb.checked; }); refresh(); }
      });
      return { cb: cb, el: h("label", null, cb, (m.full_name || m.email) + (m.active ? "" : " (o‘chiq)") +
        (office == null ? " · " + officeName(m.office_id) : "")) };
    });
    var daysInp = h("input", { type: "number", min: "0", inputmode: "numeric", placeholder: "0 — hammasi", oninput: debounce(refresh, 400) });
    var countEl = h("p", { class: "hint" });
    var err = h("div", { class: "err" });
    var expBtn = h("button", { class: "btn ghost block", text: "Excel’ga yuklab olish", onclick: doExport });
    var moveBtn = h("button", { class: "btn block", text: "Yangi lid qilib qaytarish", onclick: askMove });

    function chosen() {
      return {
        stages: stageBoxes.filter(function (b) { return b.cb.checked; }).map(function (b) { return b.cb.value; }),
        all: allCb.checked,
        mgrs: mgrBoxes.filter(function (b) { return b.cb.checked; }).map(function (b) { return b.cb.value; }),
        days: Math.max(0, Number(daysInp.value) || 0)
      };
    }
    function invalid(c) {
      if (!c.stages.length) return "Kamida bitta bosqich tanlang";
      if (!c.all && !c.mgrs.length) return "Kamida bitta menejer tanlang";
      return "";
    }
    function apply(q, c) {
      if (office != null) q = q.eq("office_id", office);
      q = q.in("stage", c.stages);
      q = c.all ? q.not("manager_id", "is", null) : q.in("manager_id", c.mgrs);
      if (c.days > 0) q = q.lt("updated_at", new Date(Date.now() - c.days * 864e5).toISOString());
      return q;
    }

    var seq = 0;
    async function refresh() {
      var c = chosen(), bad = invalid(c), my = ++seq;
      err.textContent = bad;
      expBtn.disabled = moveBtn.disabled = true;
      clear(countEl);
      if (bad) return;
      countEl.textContent = "Hisoblanmoqda…";
      var r = await apply(sb.from("leads").select("id", { count: "exact", head: true }), c);
      if (my !== seq) return;
      clear(countEl);
      if (r.error) { err.textContent = errText(r.error); return; }
      countEl.appendChild(h("b", { text: (r.count || 0) + " ta lid" }));
      countEl.appendChild(document.createTextNode(" shu shartlarga mos keladi"));
      expBtn.disabled = moveBtn.disabled = !r.count;
    }

    async function doExport() {
      var c = chosen(); if (invalid(c)) return;
      var label = expBtn.textContent;
      expBtn.disabled = true; err.textContent = "";
      try {
        var rows = [];
        for (var from = 0; ; from += 1000) {
          expBtn.textContent = "Yuklanmoqda… " + rows.length;
          var r = await apply(sb.from("leads").select("id,name,phone,stage,manager_id,office_id,updated_at,note"), c)
            .order("id").range(from, from + 999);
          if (r.error) throw r.error;
          rows = rows.concat(r.data);
          if (r.data.length < 1000) break;
        }
        await loadScript(XLSX_URL);
        // every cell is a string: phone numbers must stay text, otherwise Excel turns them into 9.98E+11
        var aoa = [["Ism", "Telefon", "Bosqich", "Menejer", "Ofis", "Oxirgi o‘zgarish", "Izoh"]].concat(rows.map(function (x) {
          return [x.name || "", String(x.phone || ""), STAGE_NAME[x.stage] || x.stage, staffName(x.manager_id) || "",
            officeName(x.office_id), fmtDate(x.updated_at), x.note || ""];
        }));
        var ws = window.XLSX.utils.aoa_to_sheet(aoa);
        ws["!cols"] = [{ wch: 24 }, { wch: 16 }, { wch: 16 }, { wch: 22 }, { wch: 14 }, { wch: 16 }, { wch: 40 }];
        var wb = window.XLSX.utils.book_new();
        window.XLSX.utils.book_append_sheet(wb, ws, "Lidlar");
        var d = new Date();
        window.XLSX.writeFile(wb, "ayol360-qayta-ishlash-" + d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() + ".xlsx");
        toast(rows.length + " ta raqam yuklab olindi");
      } catch (e) { err.textContent = errText(e); }
      expBtn.textContent = label;
      expBtn.disabled = false;
    }

    function askMove() {
      var c = chosen(); if (invalid(c)) return;
      var mErr = h("div", { class: "err" });
      modal(function (close) {
        return [
          h("h2", { text: "Yangi lid qilib qaytarish" }),
          h("p", { class: "hint", text: countEl.textContent + ". Ular menejerlardan olinadi va \"Yangi lid\" bo‘limiga menejersiz qaytadi. Izoh va tarix saqlanadi. Keyin \"Lidlar → Yangi lid → Menejersiz → Tanlash\" orqali qayta taqsimlaysiz." }),
          mErr,
          h("div", { class: "row" },
            h("button", { class: "btn line", text: "Bekor", onclick: close }),
            h("button", {
              class: "btn", text: "Ha, qaytarish",
              onclick: async function (e) {
                e.target.disabled = true;
                var r = await apply(sb.from("leads").update(BACK_TO_POOL), c).select("id");
                if (r.error) { mErr.textContent = errText(r.error); e.target.disabled = false; return; }
                close();
                toast(r.data.length + " ta lid \"Yangi lid\"ga qaytarildi");
                refresh();
              }
            }))
        ];
      });
    }

    mainEl.appendChild(h("div", { class: "box" },
      h("h3", { text: "Qayta ishlash" }),
      h("p", { class: "hint", text: "Menejerlarda qolib ketgan lidlarni Excel’ga yuklab oling yoki to‘g‘ridan-to‘g‘ri \"Yangi lid\" bo‘limiga menejersiz qaytaring." }),
      h("label", { text: "Bosqichlar" }),
      h("div", { class: "picker" }, stageBoxes.map(function (b) { return b.el; })),
      h("label", { text: "Menejerlar" }),
      h("div", { class: "picker" }, h("label", null, allCb, h("b", { text: "Barcha menejerlar" })), mgrBoxes.map(function (b) { return b.el; })),
      h("label", { text: "Necha kundan beri o‘zgarmagan (ixtiyoriy)" }), daysInp,
      countEl, err, expBtn, moveBtn));
    refresh();
  }

  // ---------------- transfer (super admin): one branch's leads to another branch's admin ----------------
  function renderTransfer() {
    function offOptions(first) {
      return [h("option", { value: "", text: first })].concat(offices.map(function (o) {
        return h("option", { value: o.id, text: officeWithAdmin(o.id) });
      }));
    }
    var fromSel = h("select", { onchange: refresh }, offOptions("— filialni tanlang —"));
    if (ui.office) fromSel.value = ui.office;
    var toSel = h("select", { onchange: refresh }, offOptions("— filialni tanlang —"));
    // all stages pre-checked: "every row" of the branch (leads without a manager are in "Yangi lid")
    var boxes = STAGES.map(function (s) {
      var cb = h("input", { type: "checkbox", value: s[0], checked: true, onchange: function () { allCb.checked = boxes.every(function (b) { return b.cb.checked; }); refresh(); } });
      return { cb: cb, el: h("label", null, cb, s[1]) };
    });
    var allCb = h("input", {
      type: "checkbox", checked: true,
      onchange: function () { boxes.forEach(function (b) { b.cb.checked = allCb.checked; }); refresh(); }
    });
    var countEl = h("p", { class: "hint" });
    var err = h("div", { class: "err" });
    var btn = h("button", { class: "btn block", text: "O‘tkazish", onclick: ask });

    function chosen() {
      return {
        from: fromSel.value ? Number(fromSel.value) : null,
        to: toSel.value ? Number(toSel.value) : null,
        keys: boxes.filter(function (b) { return b.cb.checked; }).map(function (b) { return b.cb.value; }),
        all: allCb.checked
      };
    }
    function invalid(c) {
      if (c.from == null) return "Qaysi filialdan o‘tkazishni tanlang";
      if (!c.keys.length) return "Kamida bitta qatorni tanlang";
      if (c.to == null) return "Qaysi filial adminiga o‘tkazishni tanlang";
      if (c.to === c.from) return "Boshqa filialni tanlang";
      return "";
    }
    function apply(q, c) {
      q = q.eq("office_id", c.from);
      return c.all ? q : q.in("stage", c.keys);
    }

    var seq = 0;
    async function refresh() {
      var c = chosen(), my = ++seq;
      btn.disabled = true;
      clear(countEl);
      err.textContent = "";
      if (c.from == null || !c.keys.length) { err.textContent = invalid(c); return; }
      countEl.textContent = "Hisoblanmoqda…";
      var r = await apply(sb.from("leads").select("id", { count: "exact", head: true }), c);
      if (my !== seq) return;
      clear(countEl);
      if (r.error) { err.textContent = errText(r.error); return; }
      countEl.appendChild(h("b", { text: (r.count || 0) + " ta lid" }));
      countEl.appendChild(document.createTextNode(" " + officeName(c.from) + " filialida tanlangan qatorlarda"));
      err.textContent = invalid(c);
      btn.disabled = !r.count || !!invalid(c);
    }

    function ask() {
      var c = chosen(); if (invalid(c)) return;
      var fields = Object.assign({ office_id: c.to }, BACK_TO_POOL);
      var mErr = h("div", { class: "err" });
      modal(function (close) {
        return [
          h("h2", { text: "Filialga o‘tkazish" }),
          h("p", { class: "hint", text: countEl.textContent + ". Ular " + officeName(c.from) + " menejerlaridan olinib, " +
            officeWithAdmin(c.to) + " — \"Yangi lid\" bo‘limiga menejersiz tushadi. Izoh va tarix saqlanadi." }),
          mErr,
          h("div", { class: "row" },
            h("button", { class: "btn line", text: "Bekor", onclick: close }),
            h("button", {
              class: "btn", text: "Ha, o‘tkazish",
              onclick: async function (e) {
                e.target.disabled = true;
                var r = await apply(sb.from("leads").update(fields), c).select("id");
                if (r.error) { mErr.textContent = errText(r.error); e.target.disabled = false; return; }
                close();
                toast(r.data.length + " ta lid " + officeName(c.to) + " filialiga o‘tkazildi");
                refresh();
              }
            }))
        ];
      });
    }

    mainEl.appendChild(h("div", { class: "box" },
      h("h3", { text: "Filialdan filialga o‘tkazish" }),
      h("p", { class: "hint", text: "Bir filialdagi lidlarni boshqa filial adminiga o‘tkazing. Lidlar o‘sha adminning \"Yangi lid\" bo‘limiga menejersiz tushadi va u ularni o‘z menejerlariga taqsimlaydi." }),
      h("label", { text: "Qaysi filialdan" }), fromSel,
      h("label", { text: "Qaysi qatorlar" }),
      h("div", { class: "picker" }, h("label", null, allCb, h("b", { text: "Barcha qatorlar" })), boxes.map(function (b) { return b.el; })),
      h("label", { text: "Qaysi filial adminiga" }), toSel,
      countEl, err, btn));
    refresh();
  }

  // ---------------- import ----------------
  function renderImport() {
    var office = activeOffice();
    var offSel = null;
    if (me.role === "super") {
      offSel = h("select", null, offices.map(function (o) { return h("option", { value: o.id, text: o.name }); }));
      if (office != null) offSel.value = office;
    }
    var file = h("input", { type: "file", accept: ".csv,.xlsx,.xls,text/csv" });
    var source = h("input", { placeholder: "masalan: Instagram, Tilda, Eski baza", value: "Import" });
    var out = h("div");
    mainEl.appendChild(h("div", { class: "box" },
      h("h3", { text: "Lid yuklash (Excel yoki CSV)" }),
      h("p", { class: "hint", text: "Fayl ichida ism va telefon ustuni bo‘lsin. Takroriy raqamlar ham qo‘shiladi. Yuklangan lidlar \"Yangi lid\" bo‘limiga menejersiz tushadi." }),
      offSel ? [h("label", { text: "Qaysi ofisga" }), offSel] : null,
      h("label", { text: "Manba" }), source,
      h("label", { text: "Fayl" }), file,
      out));
    file.addEventListener("change", async function () {
      clear(out);
      var f = file.files[0]; if (!f) return;
      out.appendChild(h("p", { class: "hint", text: "O‘qilmoqda…" }));
      try {
        var rows = await readTable(f);
        clear(out);
        showMapping(rows);
      } catch (e) { clear(out); out.appendChild(h("div", { class: "err", text: "Faylni o‘qib bo‘lmadi: " + errText(e) })); }
    });

    function showMapping(rows) {
      if (rows.length < 2) { out.appendChild(h("div", { class: "err", text: "Faylda ma’lumot yo‘q" })); return; }
      var head = rows[0].map(function (c) { return String(c || "").trim(); });
      var guess = function (re) { for (var i = 0; i < head.length; i++) if (re.test(head[i].toLowerCase())) return i; return -1; };
      var phoneIdx = guess(/tel|phone|raqam|номер|телефон|nomer/);
      var nameIdx = guess(/ism|name|имя|fio|фио|mijoz|клиент/);
      if (phoneIdx < 0) {
        for (var c = 0; c < head.length; c++) {
          if (rows.slice(1, 6).some(function (r) { return String(r[c] || "").replace(/\D/g, "").length >= 9; })) { phoneIdx = c; break; }
        }
      }
      function colSel(val, allowNone) {
        var s = h("select", null, allowNone ? h("option", { value: "-1", text: "— yo‘q —" }) : null,
          head.map(function (t, i) { return h("option", { value: i, text: t || ("Ustun " + (i + 1)) }); }));
        s.value = String(val);
        return s;
      }
      var phoneSel = colSel(phoneIdx < 0 ? 0 : phoneIdx, false);
      var nameSel = colSel(nameIdx, true);
      var data = rows.slice(1).filter(function (r) { return r.some(function (x) { return String(x || "").trim(); }); });
      var btn = h("button", { class: "btn block", text: data.length + " ta qatorni yuklash" });
      var res = h("div");
      out.appendChild(h("div", null,
        h("label", { text: "Telefon ustuni" }), phoneSel,
        h("label", { text: "Ism ustuni" }), nameSel,
        h("p", { class: "hint", text: "Namuna: " + data.slice(0, 3).map(function (r) {
          return (nameSel.value >= 0 ? (r[nameSel.value] || "") + " " : "") + (r[phoneSel.value] || "");
        }).join(" · ") }),
        btn, res));
      btn.onclick = async function () {
        var off = offSel ? Number(offSel.value) : office;
        var pI = Number(phoneSel.value), nI = Number(nameSel.value);
        var payload = data.map(function (r) {
          return { phone: String(r[pI] == null ? "" : r[pI]), name: nI >= 0 ? String(r[nI] == null ? "" : r[nI]).trim() : "", source: source.value.trim() || "Import" };
        });
        btn.disabled = true;
        var added = 0, skipped = 0;
        for (var i = 0; i < payload.length; i += 500) {
          btn.textContent = "Yuklanmoqda… " + Math.min(i + 500, payload.length) + "/" + payload.length;
          var r = await sb.rpc("import_leads", { p_office: off, p_rows: payload.slice(i, i + 500) });
          if (r.error) { btn.disabled = false; btn.textContent = "Qayta urinish"; res.appendChild(h("div", { class: "err", text: errText(r.error) })); return; }
          added += r.data.added; skipped += r.data.skipped;
        }
        btn.textContent = "Tayyor";
        clear(res).appendChild(h("p", null, h("b", { text: added + " ta yangi lid qo‘shildi. " }),
          skipped + " ta qator o‘tkazib yuborildi (noto‘g‘ri raqam)."));
        toast("Yuklandi: " + added);
      };
    }
  }

  function readTable(f) {
    var name = f.name.toLowerCase();
    if (/\.csv$|\.txt$/.test(name)) {
      return f.arrayBuffer().then(function (buf) {
        var text = new TextDecoder("utf-8").decode(buf);
        if (text.indexOf("�") >= 0) text = new TextDecoder("windows-1251").decode(buf);
        return parseCsv(text.replace(/^﻿/, ""));
      });
    }
    return loadScript(XLSX_URL).then(function () {
      return f.arrayBuffer().then(function (buf) {
        var wb = window.XLSX.read(buf, { type: "array" });
        var ws = wb.Sheets[wb.SheetNames[0]];
        return window.XLSX.utils.sheet_to_json(ws, { header: 1, raw: false, defval: "" });
      });
    });
  }
  function parseCsv(text) {
    var first = text.split(/\r?\n/)[0] || "";
    var sep = (first.split(";").length > first.split(",").length) ? ";" : ",";
    var rows = [], row = [], cell = "", q = false;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (q) {
        if (ch === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; }
        else cell += ch;
      } else if (ch === '"') q = true;
      else if (ch === sep) { row.push(cell); cell = ""; }
      else if (ch === "\n" || ch === "\r") {
        if (ch === "\r" && text[i + 1] === "\n") i++;
        row.push(cell); rows.push(row); row = []; cell = "";
      } else cell += ch;
    }
    if (cell || row.length) { row.push(cell); rows.push(row); }
    return rows;
  }
  var scripts = {};
  function loadScript(src) {
    if (!scripts[src]) scripts[src] = new Promise(function (ok, bad) {
      var s = document.createElement("script"); s.src = src; s.onload = ok; s.onerror = bad;
      document.head.appendChild(s);
    });
    return scripts[src];
  }

  // ---------------- staff ----------------
  function renderStaff() {
    var office = activeOffice();
    var nameI = h("input", { placeholder: "Ism Familiya" });
    var loginI = h("input", { placeholder: "masalan: dilnoza1", autocapitalize: "none" });
    var passI = h("input", { placeholder: "kamida 6 belgi", autocomplete: "new-password" });
    var roleSel = null, offSel = null;
    if (me.role === "super") {
      roleSel = h("select", null, h("option", { value: "manager", text: "Menejer" }), h("option", { value: "admin", text: "Ofis admini" }), h("option", { value: "super", text: "Bosh admin" }));
      offSel = h("select", null, offices.map(function (o) { return h("option", { value: o.id, text: o.name }); }));
      if (office != null) offSel.value = office;
    }
    var err = h("div", { class: "err" });
    var btn = h("button", { class: "btn block", text: "Xodim qo‘shish" });
    btn.onclick = async function () {
      err.textContent = "";
      var login = loginI.value.trim().toLowerCase();
      if (!nameI.value.trim() || !login || passI.value.length < 6) { err.textContent = "Ism, login va kamida 6 belgili parol kiriting"; return; }
      if (!/^[a-z0-9._@-]+$/.test(login)) { err.textContent = "Login faqat lotin harf, raqam, nuqta va chiziqchadan iborat bo‘lsin"; return; }
      btn.disabled = true;
      try {
        var role = roleSel ? roleSel.value : "manager";
        var off = offSel ? Number(offSel.value) : me.office_id;
        var s = await sb.rpc("create_staff", { p_login: login, p_password: passI.value, p_name: nameI.value.trim(), p_role: role, p_office: off });
        if (s.error) throw s.error;
        toast("Qo‘shildi: " + login);
        await loadStaff(); renderTab(false);
      } catch (e) { err.textContent = errText(e); }
      btn.disabled = false;
    };

    mainEl.appendChild(h("div", { class: "box" },
      h("h3", { text: "Yangi xodim" }),
      h("label", { text: "Ism" }), nameI,
      h("label", { text: "Login" }), loginI,
      h("label", { text: "Parol" }), passI,
      roleSel ? [h("label", { text: "Rol" }), roleSel, h("label", { text: "Ofis" }), offSel] : null,
      btn, err,
      h("p", { class: "hint", text: "Xodim shu login va parol bilan kiradi. Parolni xodimga shaxsan bering." })));

    var people = staff.filter(function (s) { return s.id !== me.id && (office == null || s.office_id === office); });
    var box = h("div", { class: "box" }, h("h3", { text: "Xodimlar (" + people.length + ")" }));
    if (!people.length) box.appendChild(h("p", { class: "hint", text: "Hali xodim yo‘q" }));
    people.forEach(function (p) {
      box.appendChild(h("div", { class: "staff", style: "padding:10px 0;border-top:1px solid var(--line)" },
        h("div", { class: "main" },
          h("div", { style: "font-weight:600", text: p.full_name || "—" }),
          h("div", { class: "hint", text: (p.email || "").replace(LOGIN_DOMAIN, "") + " · " +
            (p.role === "admin" ? "admin" : p.role === "super" ? "bosh admin" : p.role ? "menejer" : "faollashtirilmagan") +
            (p.office_id ? " · " + officeName(p.office_id) : "") })),
        h("span", { class: "pill" + (p.active ? "" : " off"), text: p.active ? "faol" : "o‘chiq" }),
        (me.role === "super" || p.role === "manager") ? h("button", {
          class: "btn line", text: "Parol", title: "Parolni almashtirish",
          onclick: function () { resetPassword(p); }
        }) : null,
        (me.role === "super" || p.role === "manager" || !p.role) ? h("button", {
          class: "btn line", text: p.active ? "O‘chirish" : "Yoqish",
          onclick: async function () {
            var r = await sb.rpc("set_staff", { p_user: p.id, p_name: p.full_name, p_role: p.role || "manager", p_office: p.office_id || me.office_id, p_active: !p.active });
            if (r.error) return fail(r.error);
            await loadStaff(); renderTab(false);
          }
        }) : null));
    });
    mainEl.appendChild(box);
  }

  function resetPassword(p) {
    var inp = h("input", { placeholder: "yangi parol (kamida 6 belgi)", autocomplete: "new-password" });
    var err = h("div", { class: "err" });
    modal(function (close) {
      return [h("h2", { text: (p.full_name || p.email) + " — yangi parol" }),
        inp, err,
        h("div", { class: "row", style: "margin-top:14px" },
          h("button", { class: "btn line", text: "Bekor", onclick: close }),
          h("button", {
            class: "btn", text: "Saqlash",
            onclick: async function () {
              var r = await sb.rpc("set_staff_password", { p_user: p.id, p_password: inp.value });
              if (r.error) { err.textContent = errText(r.error); return; }
              close(); toast("Parol yangilandi");
            }
          }))];
    });
  }

  // ---------------- stats ----------------
  async function renderStats() {
    var holder = h("div", { class: "box" }, h("p", { class: "hint", text: "Yuklanmoqda…" }));
    mainEl.appendChild(holder);
    var r = await sb.rpc("lead_stats", { p_office: activeOffice() });
    clear(holder);
    if (r.error) return fail(r.error);
    var byM = {};
    r.data.forEach(function (x) {
      var k = x.manager_id || "_none";
      byM[k] = byM[k] || { total: 0 };
      byM[k][x.stage] = (byM[k][x.stage] || 0) + Number(x.total);
      byM[k].total += Number(x.total);
    });
    var keys = Object.keys(byM).sort(function (a, b) { return byM[b].total - byM[a].total; });
    var sum = { total: 0 };
    keys.forEach(function (k) { Object.keys(byM[k]).forEach(function (s) { sum[s] = (sum[s] || 0) + byM[k][s]; }); });
    var won = (sum.card || 0) + (sum.installment || 0) + (sum.contract || 0);
    holder.appendChild(h("h3", { text: "Umumiy" }));
    holder.appendChild(h("p", null, h("b", { text: sum.total + " ta lid" }), " · sotuv bosqichida (karta, Uzum/Paylater, shartnoma): ",
      h("b", { text: won + " ta" }), sum.total ? " (" + Math.round(won * 100 / sum.total) + "%)" : ""));
    var table = h("table", null,
      h("thead", null, h("tr", null, h("th", { text: "Menejer" }), STAGES.map(function (s) { return h("th", { class: "num", text: s[1] }); }), h("th", { class: "num", text: "Jami" }))),
      h("tbody", null, keys.map(function (k) {
        return h("tr", null, h("td", { text: k === "_none" ? "Menejersiz" : (staffName(k) || "—") }),
          STAGES.map(function (s) { return h("td", { class: "num", text: byM[k][s[0]] || "" }); }),
          h("td", { class: "num" }, h("b", { text: byM[k].total })));
      })));
    holder.appendChild(h("div", { class: "scroll-x" }, table));
  }

  // ---------------- misc ----------------
  function debounce(fn, ms) { var t; return function () { clearTimeout(t); t = setTimeout(fn, ms); }; }

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible" && me && ui.tab === "leads" && !document.querySelector(".sheet") && !list.selecting) {
      restoreScroll = window.scrollY; reloadLeads(true);
    }
  });
  sb.auth.onAuthStateChange(function (ev, session) {
    if (!me) return;
    if (ev === "SIGNED_OUT" || !session) {
      resetState();
      renderLogin("Sessiya tugadi. Iltimos, qayta kiring.");
      return;
    }
    // Another tab signed in with a different account: reload so this tab shows that account correctly
    if (session.user && session.user.id !== me.id) location.reload();
  });

  boot().catch(function (e) { console.error(e); clear(app).appendChild(h("div", { class: "boot", text: "Xato: " + errText(e) })); });
})();

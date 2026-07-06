/* NW-ZT Console — 描画ロジック（vanilla JS・外部依存ゼロ） */
(function () {
  "use strict";
  var D = window.NWZT_DATA;
  if (!D) { document.body.innerHTML = "<p style='padding:40px'>データが読み込めませんでした（data.js）。</p>"; return; }

  /* ---- helpers ---- */
  function esc(s){ return String(s==null?"":s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];}); }
  function h(html){ var t=document.createElement("template"); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  var VIEWS = ["overview","nac","ztna","ndr","microseg"];
  var TITLES = { overview:"概要 / ヘルス", nac:D.nac.title, ztna:D.ztna.title, ndr:D.ndr.title, microseg:D.microseg.title };

  var TONE = {
    trust:{fill:"#e9f4ed",line:"#a9cdb7",ink:"#2f6b47"},
    dmz:{fill:"#fff4df",line:"#e0c281",ink:"#8a5a12"},
    untrust:{fill:"#f9ece8",line:"#e0af9d",ink:"#a24a37"},
    obs:{fill:"#f0edf8",line:"#c3b8e2",ink:"#5b4a8a"}
  };
  var VERDICT = { checked:"#087da8", allow:"#2f8f5b", deny:"#b8483c", observe:"#5b4a8a" };
  var VERDICT_LABEL = { checked:"検証", allow:"許可", deny:"拒否", observe:"観測" };

  /* ---- header ---- */
  document.getElementById("brandSub").textContent = D.meta.subtitle;
  document.getElementById("capAt").textContent = D.meta.capturedAt;
  document.getElementById("capSrc").textContent = D.meta.source;
  document.getElementById("postureLabel").textContent = D.meta.posture.label;
  document.getElementById("repoLink").textContent = D.meta.repo;

  /* ============ 概要 / ヘルス ============ */
  function renderOverview(){
    var m=D.meta, root=document.getElementById("v-overview");
    var kpis = m.kpis.map(function(k){
      var val = k.total!=null ? '<span class="k-val tnum">'+k.value+'<small>/ '+k.total+' '+(k.unit||"")+'</small></span>'
                              : '<span class="k-val tnum">'+k.value+'<small>'+(k.unit||"")+'</small></span>';
      return '<div class="kpi t-'+k.tone+'" data-go="'+k.nav+'">'+
        '<div class="k-label">'+esc(k.label)+'</div>'+val+
        '<div class="k-sub">'+esc(k.sub)+'</div></div>';
    }).join("");

    root.innerHTML =
      '<h2 class="sec-head">概要 / ヘルス</h2>'+
      '<p class="sec-lead">ネットワーク中心ゼロトラストの 4 観点を 1 画面で。まず「状態」を見せ、詳細は各セクションへ。'+
        'すべて実機検証ラボ（OSS × arm64）から採取した実データ。</p>'+
      '<div class="kpis">'+kpis+'</div>'+
      '<div class="panel">'+
        '<div class="panel-h"><h3>ゾーン構成と通信の可否</h3><span class="hint">Untrust → DMZ(認可) → Trust。横断は「認可済みのみ」</span></div>'+
        '<div class="map">'+zoneMap(m)+'</div>'+
        '<div class="legend">'+
          '<span><i style="background:#087da8"></i>検証（認証/認可）</span>'+
          '<span><i style="background:#2f8f5b"></i>許可</span>'+
          '<span><i style="background:#b8483c"></i>拒否（default-deny）</span>'+
          '<span><i style="background:#5b4a8a"></i>観測（ログ/verdict）</span>'+
        '</div>'+
      '</div>';
    root.querySelectorAll(".kpi").forEach(function(c){ c.addEventListener("click",function(){ go(c.getAttribute("data-go")); }); });
  }

  /* ---- ゾーンマップ（署名の SVG・自前描画） ---- */
  function zoneMap(m){
    var W=920, H=290, pad=14, n=m.zones.length;
    var zw=192, gap=(W - pad*2 - zw*n)/(n-1), zy=64, zh=176;
    var pos={};
    var zoneSVG = m.zones.map(function(z,i){
      var x=pad + i*(zw+gap); pos[z.id]={x:x,w:zw,cx:x+zw/2,y:zy,h:zh};
      var t=TONE[z.tone];
      var nodes = z.nodes.map(function(nd,j){
        var ny=zy+42 + j*38;
        return '<g transform="translate('+(x+14)+','+ny+')">'+
          '<rect width="'+(zw-28)+'" height="28" rx="8" fill="#fffefa" stroke="'+t.line+'"/>'+
          '<circle cx="15" cy="14" r="4" fill="'+t.ink+'"/>'+
          '<text x="28" y="18" font-size="12" fill="#17232d" font-weight="600">'+esc(nd.n)+'</text>'+
          '<text x="'+(zw-40)+'" y="18" font-size="10.5" fill="#8a97a0" text-anchor="end">'+esc(nd.t)+'</text>'+
        '</g>';
      }).join("");
      return '<g>'+
        '<rect x="'+x+'" y="'+zy+'" width="'+zw+'" height="'+zh+'" rx="14" fill="'+t.fill+'" stroke="'+t.line+'"/>'+
        '<text x="'+(x+14)+'" y="'+(zy+24)+'" font-size="12.5" font-weight="700" fill="'+t.ink+'" letter-spacing=".02em">'+esc(z.name)+'</text>'+
        nodes+'</g>';
    }).join("");

    // フロー矢印
    var arrows = m.flows.map(function(f){
      var a=pos[f.from], b=pos[f.to]; if(!a||!b) return "";
      var col=VERDICT[f.verdict]||"#5c6b75";
      var adjacent = Math.abs((a.x)-(b.x)) <= (zw+gap)+2;
      if(f.verdict==="deny" || !adjacent){
        // 上をまたぐ弧（直接到達の拒否など）
        var x1=a.cx, x2=b.cx, top=zy-34;
        var d="M "+x1+" "+zy+" C "+x1+" "+top+" "+x2+" "+top+" "+x2+" "+zy;
        var dash = f.verdict==="deny" ? ' stroke-dasharray="6 5"' : "";
        return '<path d="'+d+'" fill="none" stroke="'+col+'" stroke-width="2"'+dash+'/>'+
          '<text x="'+((x1+x2)/2)+'" y="'+(top-4)+'" text-anchor="middle" font-size="11" font-weight="700" fill="'+col+'">'+esc(f.label)+'</text>'+
          arrowHead((x2>x1?x2-6:x2+6), zy, col, x2>x1?0:180);
      }
      // 隣接ゾーン間の水平矢印
      var y=zy+zh+22, sx=a.x+a.w, ex=b.x;
      var mx=(sx+ex)/2;
      return '<path d="M '+sx+' '+(zy+zh/2)+' C '+(sx+24)+' '+(zy+zh/2)+' '+(ex-24)+' '+(zy+zh/2)+' '+ex+' '+(zy+zh/2)+'" fill="none" stroke="'+col+'" stroke-width="2"/>'+
        arrowHead(ex-6, zy+zh/2, col, 0)+
        '<rect x="'+(mx-42)+'" y="'+(zy+zh/2-11)+'" width="84" height="22" rx="11" fill="#fffefa" stroke="'+col+'" opacity=".96"/>'+
        '<text x="'+mx+'" y="'+(zy+zh/2+4)+'" text-anchor="middle" font-size="10.5" font-weight="700" fill="'+col+'">'+esc(f.label)+'</text>';
    }).join("");

    return '<svg class="zonemap" viewBox="0 0 '+W+' '+H+'" role="img" aria-label="ゾーン構成図">'+zoneSVG+arrows+'</svg>';
  }
  function arrowHead(x,y,col,rot){ return '<path transform="translate('+x+','+y+') rotate('+rot+')" d="M 0 0 L -7 -4 L -7 4 Z" fill="'+col+'"/>'; }

  /* ============ NAC ============ */
  function renderNac(){
    var d=D.nac, root=document.getElementById("v-nac");
    var rows=d.sessions.map(function(s){
      var st = s.status==="Authorized" ? '<span class="pill ok">'+esc(s.status)+'</span>'
                                       : '<span class="pill no">'+esc(s.status)+'</span>';
      var vl = s.vlan==="—" ? '<span class="vlan q">'+esc(s.vlanName)+'</span>'
                            : '<span class="vlan">VLAN '+esc(s.vlan)+' · '+esc(s.vlanName)+'</span>';
      return '<tr><td class="strong">'+esc(s.user)+'</td><td><span class="mono">'+esc(s.mac)+'</span></td>'+
        '<td><span class="mono">'+esc(s.port)+'</span></td><td>'+vl+'</td>'+
        '<td>'+esc(s.method)+'</td><td>'+st+'</td></tr>';
    }).join("");
    var intents=d.policy.rows.map(function(r){
      return '<div class="intent"><span class="kind">ACCESS</span><span class="who">'+esc(r.who)+'</span>'+
        '<span class="arrow">→</span><span class="what">'+esc(r.vlan)+'</span><span class="via">'+esc(r.via)+'</span></div>';
    }).join("");
    root.innerHTML = secHead(d)+
      '<div class="card"><div class="card-h"><h3>クライアント / セッション</h3><span class="sub">認証済 '+d.summary.authorized+' · 未認証 '+d.summary.unauthorized+'</span></div>'+
        '<table><thead><tr><th>ユーザー</th><th>MAC</th><th>ポート</th><th>VLAN</th><th>方式</th><th>状態</th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
      '<div class="card"><div class="card-h"><h3>アクセスポリシー <span class="sub">意図: '+esc(d.policy.intent)+'</span></h3></div>'+intents+'</div>'+
      '<p class="insight">'+esc(d.proof)+'</p>';
  }

  /* ============ ZTNA ============ */
  function renderZtna(){
    var d=D.ztna, root=document.getElementById("v-ztna");
    var svc=d.services.map(function(s){
      return '<tr><td class="strong">'+esc(s.name)+'</td>'+
        '<td>'+(s.dark?'<span class="pill dark">DARK · 内向き0</span>':'<span class="pill ok">公開</span>')+'</td>'+
        '<td>'+esc(s.hostedBy)+'</td><td><span class="mono">'+esc(s.target)+'</span></td></tr>';
    }).join("");
    var ids=d.identities.map(function(i){
      return '<tr><td class="strong">'+esc(i.name)+'</td><td>'+esc(i.role)+'</td>'+
        '<td>'+(i.enrolled?'<span class="pill ok">enrolled</span>':'<span class="pill no">pending</span>')+'</td></tr>';
    }).join("");
    var intents=d.policy.rows.map(function(r){
      return '<div class="intent"><span class="kind">'+esc(r.type)+'</span><span class="who">'+esc(r.who)+'</span>'+
        '<span class="arrow">→</span><span class="what">'+esc(r.what)+'</span></div>';
    }).join("");
    root.innerHTML = secHead(d)+
      '<div class="two">'+
        '<div class="card"><div class="card-h"><h3>サービス</h3><span class="sub">'+d.summary.services+' 件 · dark '+d.summary.dark+'</span></div>'+
          '<table><thead><tr><th>サービス</th><th>可視性</th><th>hosted by</th><th>実体</th></tr></thead><tbody>'+svc+'</tbody></table></div>'+
        '<div class="card"><div class="card-h"><h3>アイデンティティ</h3></div>'+
          '<table><thead><tr><th>名前</th><th>ロール</th><th>状態</th></tr></thead><tbody>'+ids+'</tbody></table></div>'+
      '</div>'+
      '<div class="card"><div class="card-h"><h3>アクセスポリシー <span class="sub">意図: '+esc(d.policy.intent)+'</span></h3></div>'+intents+'</div>'+
      '<div class="card"><div class="card-h"><h3>実測（ダークサービスの証拠）</h3></div>'+
        '<div class="proof">'+
          '<div class="p ok"><div class="lab">client → overlay → app</div><div class="val">'+esc(d.proof.overlay)+'</div></div>'+
          '<div class="p deny"><div class="lab">client → app（直接）</div><div class="val">'+esc(d.proof.direct)+'</div></div>'+
        '</div><p class="note">'+esc(d.proof.note)+'</p></div>';
  }

  /* ============ NDR ============ */
  function renderNdr(){
    var d=D.ndr, root=document.getElementById("v-ndr");
    var al=d.alerts.map(function(a){
      var sc = a.severity<=2 ? "high" : (a.severity===3?"med":"low");
      return '<tr><td><span class="mono">'+a.sid+'</span></td><td class="strong">'+esc(a.sig)+'</td>'+
        '<td><span class="mono">'+esc(a.src)+' → '+esc(a.dst)+'</span></td><td>'+esc(a.proto)+'</td>'+
        '<td><span class="sev '+sc+'"><i></i>'+esc(a.sevLabel)+'</span></td><td><span class="mono">'+esc(a.iface)+'</span></td></tr>';
    }).join("");
    var tt=d.topTalkers.map(function(t){
      return '<div class="mrow"><span class="src mono">'+esc(t.src)+'</span><span class="flow">→</span>'+
        '<span class="dst mono">'+esc(t.dst)+'</span><span class="cnt">'+t.flows+' flows</span>'+
        '<span class="layer">'+esc(t.kind)+'</span></div>';
    }).join("");
    root.innerHTML = secHead(d)+
      '<div class="kpis" style="grid-template-columns:repeat(3,1fr)">'+
        '<div class="kpi t-untrust"><div class="k-label">アラート</div><div class="k-val tnum">'+d.summary.alerts+'</div><div class="k-sub">高 '+d.summary.high+' / 中 '+d.summary.medium+'</div></div>'+
        '<div class="kpi t-dmz"><div class="k-label">観測フロー</div><div class="k-val tnum">'+d.summary.flows+'</div><div class="k-sub">east-west 5-tuple</div></div>'+
        '<div class="kpi t-obs"><div class="k-label">重大</div><div class="k-val tnum">'+d.summary.critical+'</div><div class="k-sub">現在 0 件</div></div>'+
      '</div>'+
      '<div class="card"><div class="card-h"><h3>検知アラート（east-west）</h3></div>'+
        '<table><thead><tr><th>SID</th><th>シグネチャ</th><th>src → dst</th><th>proto</th><th>重大度</th><th>i/f</th></tr></thead><tbody>'+al+'</tbody></table></div>'+
      '<div class="card"><div class="card-h"><h3>Top Talkers</h3><span class="sub">横方向の偏り</span></div>'+tt+'</div>'+
      '<p class="insight">'+esc(d.proof)+'</p>';
  }

  /* ============ Microseg ============ */
  function renderMicro(){
    var d=D.microseg, root=document.getElementById("v-microseg");
    function approachBody(ap){
      var rows=ap.rules.map(function(r){
        var cls=r.verdict==="allow"?"allow":"deny";
        return '<div class="mrow '+cls+'"><span class="src strong">'+esc(r.from)+'</span><span class="flow">→</span>'+
          '<span class="dst">'+esc(r.to)+'</span>'+
          '<span class="pill '+(r.verdict==="allow"?"ok":"deny")+'">'+(r.verdict==="allow"?"許可":"拒否")+' · '+esc(r.counter)+'</span>'+
          '<span class="layer">'+esc(r.layer)+'</span></div>';
      }).join("");
      return rows+'<p class="insight">'+esc(ap.insight)+'</p>';
    }
    var tabs=d.approaches.map(function(ap,i){ return '<button data-ap="'+ap.id+'"'+(i===0?' class="on"':'')+'>'+esc(ap.name)+'</button>'; }).join("");
    root.innerHTML = secHead(d)+
      '<div class="card"><div class="approach-tabs">'+tabs+'</div>'+
        '<div id="apBody">'+approachBody(d.approaches[0])+'</div></div>'+
      '<p class="note">同じ「横移動の遮断」を 2 つの OSS で実装。IOL VLAN/ACL は L2/L3 の粗い分離＋ホスト nftables で同一 VLAN 内、Cilium は Identity ベースで L4/L7 を宣言的に。</p>';
    var body=root.querySelector("#apBody");
    root.querySelectorAll(".approach-tabs button").forEach(function(b){
      b.addEventListener("click",function(){
        root.querySelectorAll(".approach-tabs button").forEach(function(x){x.classList.remove("on");});
        b.classList.add("on");
        var ap=d.approaches.filter(function(a){return a.id===b.getAttribute("data-ap");})[0];
        body.innerHTML=approachBody(ap);
      });
    });
  }

  function secHead(d){
    return '<h2 class="sec-head">'+esc(d.title)+'</h2>'+
      '<div class="map-pair"><span class="chip">商用 <b>'+esc(d.commercial)+'</b></span>'+
      '<span class="chip oss">OSS <b>'+esc(d.oss)+'</b></span>'+
      '<span class="chip">theme <b>'+esc(d.theme)+'</b></span></div>';
  }

  /* ---- ルーティング ---- */
  var rendered={};
  function render(v){
    if(rendered[v]) return;
    ({overview:renderOverview,nac:renderNac,ztna:renderZtna,ndr:renderNdr,microseg:renderMicro})[v]();
    rendered[v]=true;
  }
  function go(v){
    if(VIEWS.indexOf(v)<0) v="overview";
    render(v);
    document.querySelectorAll(".view").forEach(function(s){ s.classList.toggle("on", s.getAttribute("data-view")===v); });
    document.querySelectorAll(".nav a").forEach(function(a){ a.classList.toggle("active", a.getAttribute("data-view")===v); });
    document.getElementById("viewTitle").textContent = TITLES[v];
    document.getElementById("viewCrumb").textContent = v==="overview" ? "single pane of glass" : "ゼロトラスト観点 / "+TITLES[v];
    if(location.hash!=="#"+v) history.replaceState(null,"","#"+v);
    document.querySelector(".main").scrollTo?document.querySelector(".main").scrollTo(0,0):0;
  }
  document.querySelectorAll(".nav a").forEach(function(a){ a.addEventListener("click",function(e){ e.preventDefault(); go(a.getAttribute("data-view")); }); });
  window.addEventListener("hashchange",function(){ go(location.hash.replace("#","")); });

  render("overview");
  go((location.hash||"#overview").replace("#",""));
})();

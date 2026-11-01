// SoulVerdict offline GUI renderer — browser side.
// Reads window.__GUI__ (tools/lune/dump_gui.luau JSON) and window.__FONTMAP__, lays the tree out with
// Roblox semantics and renders absolutely positioned DOM nodes. Exposes window.__render() (async).
//
// Implemented Roblox semantics
//   * UDim2 Size/Position (scale + offset) against the parent's absolute size AFTER UIPadding, SizeConstraint
//   * AnchorPoint, Rotation (about the centre; inherited by descendants), ZIndex with Sibling behaviour
//   * UIScale (scales the object about its AnchorPoint and every descendant), AutomaticSize X/Y/XY
//   * UIListLayout: FillDirection, Padding, SortOrder, Horizontal/VerticalAlignment, Wraps,
//     HorizontalFlex/VerticalFlex (Fill, SpaceBetween, SpaceAround, SpaceEvenly), ItemLineAlignment, UIFlexItem
//   * UIGridLayout: CellSize, CellPadding, FillDirection, FillDirectionMaxCells, alignment, nested aspect
//   * UIAspectRatioConstraint (FitWithinMaxSize, ScaleWithParentSize + DominantAxis), UISizeConstraint,
//     UITextSizeConstraint, TextScaled fitting (<= 100)
//   * UICorner (scale = fraction of the shortest side, clamped), UIStroke Border (Outer/Center/Inner + BorderOffset,
//     LineJoin round/miter, gradient strokes) and Contextual text strokes, legacy TextStroke
//   * UIGradient (Color x base colour, Transparency, Rotation, Offset) in Roblox UV space; on text = gradient fill
//   * ClipsDescendants (ignored when the object or an ancestor is rotated, like Roblox), CanvasGroup
//     (GroupTransparency, clipping with corner radius), ScrollingFrame canvas + scrollbar, ViewportFrame placeholder
//   * Text: TextSize = line height (font size normalised by ascent+descent), LineHeight, X/Y alignment,
//     TextWrapped, TextTruncate, MaxVisibleGraphemes, RichText subset (b, i, u, s, br, font, stroke, uc, sc, mark)
(function () {
	'use strict';

	const GUI = new Set(['Frame', 'TextLabel', 'TextButton', 'TextBox', 'ImageLabel', 'ImageButton', 'ScrollingFrame', 'ViewportFrame', 'CanvasGroup', 'VideoFrame']);
	const TEXT = new Set(['TextLabel', 'TextButton', 'TextBox']);
	const WEIGHTS = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };
	const FONT_MAP = window.__FONTMAP__ || {};
	const OPTS = window.__OPTS__ || {};

	const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
	const udim = (u, base) => (u ? u[0] * base + u[1] : 0);

	// ---------------------------------------------------------------------------------------------
	// fonts
	function familyKey(fam) {
		const m = /families\/([^/.]+)\.json/.exec(fam || '');
		return m ? m[1] : 'SourceSansPro';
	}
	function cssFont(face) {
		const f = face || { family: 'rbxasset://fonts/families/SourceSansPro.json', weight: 'Regular', style: 'Normal' };
		const key = familyKey(f.family);
		const web = (FONT_MAP[key] || ['Source Sans 3'])[0];
		return { family: `"${web}"`, weight: WEIGHTS[f.weight] || 400, style: f.style === 'Italic' ? 'italic' : 'normal', key };
	}
	const metricCache = new Map();
	const cv = document.createElement('canvas');
	const c2d = cv.getContext('2d');
	function lineFactor(cf) {
		const k = `${cf.family}|${cf.weight}|${cf.style}`;
		if (metricCache.has(k)) return metricCache.get(k);
		c2d.font = `${cf.style} ${cf.weight} 100px ${cf.family}`;
		const m = c2d.measureText('Hg');
		let f = (m.fontBoundingBoxAscent + m.fontBoundingBoxDescent) / 100;
		if (!isFinite(f) || f <= 0.5) f = 1.2;
		metricCache.set(k, f);
		return f;
	}

	// ---------------------------------------------------------------------------------------------
	// colours & gradients
	const to255 = (v) => Math.round(clamp(v, 0, 1) * 255);
	const rgba = (c, a) => `rgba(${to255(c[0])},${to255(c[1])},${to255(c[2])},${clamp(a, 0, 1).toFixed(4)})`;
	function sampleColor(seq, t) {
		if (!seq || !seq.length) return [1, 1, 1];
		if (t <= seq[0][0]) return seq[0].slice(1, 4);
		for (let i = 1; i < seq.length; i++) {
			if (t <= seq[i][0]) {
				const a = seq[i - 1], b = seq[i];
				const u = (t - a[0]) / Math.max(b[0] - a[0], 1e-6);
				return [a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u];
			}
		}
		return seq[seq.length - 1].slice(1, 4);
	}
	function sampleNumber(seq, t) {
		if (!seq || !seq.length) return 0;
		if (t <= seq[0][0]) return seq[0][1];
		for (let i = 1; i < seq.length; i++) {
			if (t <= seq[i][0]) {
				const a = seq[i - 1], b = seq[i];
				const u = (t - a[0]) / Math.max(b[0] - a[0], 1e-6);
				return a[1] + (b[1] - a[1]) * u;
			}
		}
		return seq[seq.length - 1][1];
	}
	// Roblox UIGradient: t(u,v) = 0.5 + (u-0.5-offX)cos + (v-0.5-offY)sin in normalised UV space
	function cssGradient(g, w, h, base, baseAlpha) {
		const rot = ((g.p.Rotation || 0) * Math.PI) / 180;
		const c = Math.cos(rot), s = Math.sin(rot);
		const off = g.p.Offset || [0, 0];
		const W = Math.max(w, 1e-3), H = Math.max(h, 1e-3);
		const gx = c / W, gy = s / H;
		const glen = Math.hypot(gx, gy) || 1e-6;
		const A = Math.atan2(gx, -gy);
		const L = Math.abs(W * Math.sin(A)) + Math.abs(H * Math.cos(A));
		const shift = off[0] * c + off[1] * s;
		const colors = g.p.Color || [[0, 1, 1, 1], [1, 1, 1, 1]];
		const trans = g.p.Transparency || [[0, 0], [1, 0]];
		const times = new Set([0, 1]);
		colors.forEach((k) => times.add(k[0]));
		trans.forEach((k) => times.add(k[0]));
		// extra samples so non-linear merges stay smooth
		for (let i = 1; i < 16; i++) times.add(i / 16);
		const sorted = [...times].sort((a, b) => a - b);
		const stops = sorted.map((t) => {
			const col = sampleColor(colors, t);
			const tr = sampleNumber(trans, t);
			const out = [col[0] * base[0], col[1] * base[1], col[2] * base[2]];
			const p = 0.5 + (t - 0.5 + shift) / (L * glen);
			return `${rgba(out, baseAlpha * (1 - tr))} ${(p * 100).toFixed(3)}%`;
		});
		return `linear-gradient(${A}rad, ${stops.join(', ')})`;
	}
	function averageColor(g, base) {
		const c = sampleColor(g.p.Color || [[0, 1, 1, 1]], 0.5);
		return [c[0] * base[0], c[1] * base[1], c[2] * base[2]];
	}

	// ---------------------------------------------------------------------------------------------
	// tree preparation
	function prep(n, parent) {
		const node = { cls: n.class, name: n.name, p: n.props || {}, attrs: n.attrs || {}, parent, kids: [], comps: { strokes: [] }, idx: 0 };
		const children = Array.isArray(n.children) ? n.children : [];
		children.forEach((c, i) => {
			const cn = prep(c, node);
			cn.idx = i;
			switch (c.class) {
				case 'UIStroke': node.comps.strokes.push(cn); break;
				case 'UICorner': node.comps.corner = node.comps.corner || cn; break;
				case 'UIGradient': node.comps.gradient = node.comps.gradient || cn; break;
				case 'UIPadding': node.comps.padding = cn; break;
				case 'UIListLayout': node.comps.list = node.comps.list || cn; break;
				case 'UIGridLayout': node.comps.grid = node.comps.grid || cn; break;
				case 'UIAspectRatioConstraint': node.comps.aspect = cn; break;
				case 'UISizeConstraint': node.comps.sizeC = cn; break;
				case 'UITextSizeConstraint': node.comps.textC = cn; break;
				case 'UIScale': node.comps.scale = cn; break;
				case 'UIFlexItem': node.comps.flex = cn; break;
				default:
					if (GUI.has(c.class)) node.kids.push(cn);
			}
		});
		return node;
	}
	const visibleKids = (node) => node.kids.filter((k) => k.p.Visible !== false);

	// ---------------------------------------------------------------------------------------------
	// text measurement
	let measureEl;
	function richToHtml(text, cf, k) {
		// minimal Roblox RichText -> HTML
		const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
		let out = '';
		const re = /<(\/?)([a-zA-Z]+)([^>]*)>|<!--[\s\S]*?-->/g;
		let last = 0, m;
		const stack = [];
		const attr = (s, name) => {
			const r = new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, 'i').exec(s);
			return r ? r[1] : null;
		};
		while ((m = re.exec(text))) {
			out += esc(text.slice(last, m.index)).replace(/&amp;(lt|gt|quot|apos|amp);/g, '&$1;');
			last = re.lastIndex;
			if (!m[2]) continue;
			const close = m[1] === '/';
			const tag = m[2].toLowerCase();
			if (tag === 'br') { out += '<br>'; continue; }
			if (close) { const t = stack.pop(); if (t) out += '</span>'; continue; }
			let style = '';
			if (tag === 'b') style = 'font-weight:700';
			else if (tag === 'i') style = 'font-style:italic';
			else if (tag === 'u') style = 'text-decoration:underline';
			else if (tag === 's') style = 'text-decoration:line-through';
			else if (tag === 'uc' || tag === 'uppercase') style = 'text-transform:uppercase';
			else if (tag === 'sc' || tag === 'smallcaps') style = 'font-variant:small-caps';
			else if (tag === 'font') {
				const color = attr(m[3], 'color');
				const size = attr(m[3], 'size');
				const weight = attr(m[3], 'weight');
				const transparency = attr(m[3], 'transparency');
				if (color) style += `color:${/^#/.test(color) || /^rgb/.test(color) ? color : '#' + color};`;
				if (size) style += `font-size:${parseFloat(size) / k}px;`;
				if (weight) style += `font-weight:${WEIGHTS[weight] || (weight.toLowerCase() === 'bold' ? 700 : weight)};`;
				if (transparency) style += `opacity:${1 - parseFloat(transparency)};`;
			} else if (tag === 'stroke') {
				const color = attr(m[3], 'color') || '#000';
				const th = parseFloat(attr(m[3], 'thickness') || '1');
				style = `text-shadow:${ringShadows(th, color)}`;
			} else if (tag === 'mark') {
				const color = attr(m[3], 'color') || '#ff0';
				style = `background:${color}`;
			}
			stack.push(tag);
			out += `<span style="${style}">`;
		}
		out += esc(text.slice(last)).replace(/&amp;(lt|gt|quot|apos|amp);/g, '&$1;');
		while (stack.pop()) out += '</span>';
		return out;
	}
	function measureText(node, size, wrapWidth) {
		const p = node.p;
		const cf = cssFont(p.FontFace);
		const k = lineFactor(cf);
		const lh = size * (p.LineHeight || 1);
		const el = measureEl;
		el.style.fontFamily = cf.family;
		el.style.fontWeight = cf.weight;
		el.style.fontStyle = cf.style;
		el.style.fontSize = `${size / k}px`;
		el.style.lineHeight = `${lh}px`;
		if (wrapWidth != null) {
			el.style.whiteSpace = 'pre-wrap';
			el.style.width = `${Math.max(wrapWidth, 1)}px`;
			el.style.display = 'block';
		} else {
			el.style.whiteSpace = 'pre';
			el.style.width = 'auto';
			el.style.display = 'inline-block';
		}
		const text = visibleText(node);
		if (p.RichText) el.innerHTML = richToHtml(text, cf, k);
		else el.textContent = text;
		const r = el.getBoundingClientRect();
		let w = r.width;
		if (wrapWidth != null) {
			// shrink-wrap width of wrapped text
			el.style.width = 'auto';
			el.style.display = 'inline-block';
			el.style.maxWidth = `${Math.max(wrapWidth, 1)}px`;
			w = Math.min(el.getBoundingClientRect().width, wrapWidth);
			el.style.maxWidth = 'none';
		}
		const lines = Math.max(1, Math.round(r.height / lh));
		const h = text.length === 0 ? size : lines === 1 ? size : r.height - (lh - size);
		return { w: text.length === 0 ? 0 : w, h, lines };
	}
	function visibleText(node) {
		let t = node.p.Text == null ? '' : String(node.p.Text);
		const mvg = node.p.MaxVisibleGraphemes;
		if (mvg != null && mvg >= 0 && !node.p.RichText) t = [...t].slice(0, mvg).join('');
		return t;
	}
	function textSizeFor(node, boxW, boxH) {
		const p = node.p;
		if (!p.TextScaled) return p.TextSize || 14;
		const tc = node.comps.textC;
		let hi = Math.min(100, tc && tc.p.MaxTextSize ? tc.p.MaxTextSize : 100);
		let lo = Math.max(1, tc && tc.p.MinTextSize ? tc.p.MinTextSize : 1);
		if (lo > hi) return hi;
		let best = lo;
		while (lo <= hi) {
			const mid = Math.floor((lo + hi) / 2);
			const m = measureText(node, mid, p.TextWrapped ? boxW : null);
			if (m.w <= boxW + 0.5 && m.h <= boxH + 0.5) { best = mid; lo = mid + 1; } else hi = mid - 1;
		}
		return best;
	}

	// ---------------------------------------------------------------------------------------------
	// layout
	function paddingOf(node, w, h) {
		const P = node.comps.padding;
		if (!P) return { l: 0, t: 0, r: 0, b: 0 };
		return { l: udim(P.p.PaddingLeft, w), r: udim(P.p.PaddingRight, w), t: udim(P.p.PaddingTop, h), b: udim(P.p.PaddingBottom, h) };
	}
	function constrain(node, w, h) {
		const c = node.comps.sizeC;
		if (c) {
			const mn = c.p.MinSize || [0, 0], mx = c.p.MaxSize || [1e9, 1e9];
			w = clamp(w, mn[0], mx[0]);
			h = clamp(h, mn[1], mx[1]);
		}
		const a = node.comps.aspect;
		if (a) {
			const r = a.p.AspectRatio || 1;
			if ((a.p.AspectType || 'FitWithinMaxSize') === 'ScaleWithParentSize') {
				if ((a.p.DominantAxis || 'Width') === 'Width') h = w / r; else w = h * r;
			} else if (w / Math.max(h, 1e-6) > r) w = h * r; else h = w / r;
		}
		return { w: Math.max(0, w), h: Math.max(0, h) };
	}
	function baseSize(node, pw, ph) {
		const S = node.p.Size || [0, 0, 0, 0];
		const sc = node.p.SizeConstraint || 'RelativeXY';
		const bx = sc === 'RelativeYY' ? ph : pw;
		const by = sc === 'RelativeXX' ? pw : ph;
		return constrain(node, S[0] * bx + S[1], S[2] * by + S[3]);
	}
	const scaleOf = (node) => (node.comps.scale ? (node.comps.scale.p.Scale == null ? 1 : node.comps.scale.p.Scale) : 1);

	// measures node with parent content size pw x ph; lays out its subtree; returns scaled outer size
	function measure(node, pw, ph, fixed) {
		let w, h;
		if (fixed) ({ w, h } = fixed);
		else ({ w, h } = baseSize(node, pw, ph));
		node.w = w;
		node.h = h;
		layoutInside(node);
		const auto = fixed ? 'None' : node.p.AutomaticSize || 'None';
		if (auto !== 'None') {
			const pad = paddingOf(node, node.w, node.h);
			let cw = 0, ch = 0;
			const autoX = auto === 'X' || auto === 'XY';
			const autoY = auto === 'Y' || auto === 'XY';
			if (TEXT.has(node.cls) && visibleText(node).length > 0) {
				const size = node.p.TextScaled ? node.p.TextSize || 14 : node.p.TextSize || 14;
				const wrapW = node.p.TextWrapped && !autoX ? node.w - pad.l - pad.r : null;
				const m = measureText(node, size, wrapW);
				cw = m.w;
				ch = m.h;
			}
			const ext = contentExtent(node, autoX, autoY);
			cw = Math.max(cw, ext.w);
			ch = Math.max(ch, ext.h);
			let nw = node.w, nh = node.h;
			if (autoX) nw = Math.max(node.w, cw + pad.l + pad.r);
			if (autoY) nh = Math.max(node.h, ch + pad.t + pad.b);
			const c = node.comps.sizeC;
			if (c && c.p.MaxSize) { nw = Math.min(nw, c.p.MaxSize[0]); nh = Math.min(nh, c.p.MaxSize[1]); }
			if (Math.abs(nw - node.w) > 0.01 || Math.abs(nh - node.h) > 0.01) {
				node.w = nw;
				node.h = nh;
				layoutInside(node);
			}
		}
		node.s = scaleOf(node);
		return { w: node.w * node.s, h: node.h * node.s };
	}
	function contentExtent(node, autoX, autoY) {
		if (node.listContent) return { w: node.listContent.w, h: node.listContent.h };
		if (node.gridContent) return { w: node.gridContent.w, h: node.gridContent.h };
		let w = 0, h = 0;
		for (const k of visibleKids(node)) {
			const S = k.p.Size || [0, 0, 0, 0];
			const ox = k.x - (node.pad ? node.pad.l : 0);
			const oy = k.y - (node.pad ? node.pad.t : 0);
			if (!(autoX && S[0] !== 0)) w = Math.max(w, ox + k.w * k.s);
			if (!(autoY && S[2] !== 0)) h = Math.max(h, oy + k.h * k.s);
		}
		return { w, h };
	}
	function layoutInside(node) {
		const pad = paddingOf(node, node.w, node.h);
		node.pad = pad;
		node.listContent = null;
		node.gridContent = null;
		let cw = Math.max(0, node.w - pad.l - pad.r);
		let ch = Math.max(0, node.h - pad.t - pad.b);
		const kids = visibleKids(node);
		if (node.cls === 'ScrollingFrame') {
			const CS = node.p.CanvasSize || [0, 0, 0, 0];
			let canW = Math.max(node.w, CS[0] * node.w + CS[1]);
			let canH = Math.max(node.h, CS[2] * node.h + CS[3]);
			const thick = node.p.ScrollBarThickness == null ? 12 : node.p.ScrollBarThickness;
			const run = () => {
				const ccw = Math.max(0, canW - pad.l - pad.r), cch = Math.max(0, canH - pad.t - pad.b);
				layoutKids(node, kids, ccw, cch);
				return contentExtent(node, false, false);
			};
			let ext = run();
			const auto = node.p.AutomaticCanvasSize || 'None';
			if (auto === 'Y' || auto === 'XY') canH = Math.max(node.h, ext.h + pad.t + pad.b);
			if (auto === 'X' || auto === 'XY') canW = Math.max(node.w, ext.w + pad.l + pad.r);
			node.scrollY = canH > node.h + 0.5;
			if (node.scrollY && (node.p.VerticalScrollBarInset || 'None') !== 'None') canW = Math.max(0, canW - thick);
			ext = run();
			node.canvas = { w: canW, h: canH, thick };
			cw = canW - pad.l - pad.r;
			ch = canH - pad.t - pad.b;
		} else {
			layoutKids(node, kids, cw, ch);
		}
		node.cw = cw;
		node.ch = ch;
		for (const k of kids) { k.x += pad.l; k.y += pad.t; }
	}
	function layoutKids(node, kids, cw, ch) {
		if (node.comps.grid) layoutGrid(node, kids, cw, ch);
		else if (node.comps.list) layoutList(node, kids, cw, ch);
		else {
			for (const k of kids) {
				const sz = measure(k, cw, ch);
				const P = k.p.Position || [0, 0, 0, 0];
				const A = k.p.AnchorPoint || [0, 0];
				k.x = P[0] * cw + P[1] - A[0] * sz.w;
				k.y = P[2] * ch + P[3] - A[1] * sz.h;
			}
		}
	}
	function sortKids(kids, order) {
		const arr = kids.slice();
		if (order === 'Name') arr.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.idx - b.idx));
		else arr.sort((a, b) => (a.p.LayoutOrder || 0) - (b.p.LayoutOrder || 0) || a.idx - b.idx);
		return arr;
	}
	function layoutList(node, kids, cw, ch) {
		const L = node.comps.list.p;
		const hor = (L.FillDirection || 'Vertical') === 'Horizontal';
		const mainAvail = hor ? cw : ch;
		const crossAvail = hor ? ch : cw;
		const gap = L.Padding ? L.Padding[0] * mainAvail + L.Padding[1] : 0;
		const items = sortKids(kids, L.SortOrder || 'LayoutOrder');
		const sizes = new Map();
		for (const k of items) sizes.set(k, measure(k, cw, ch));
		const mainOf = (k) => (hor ? sizes.get(k).w : sizes.get(k).h);
		const crossOf = (k) => (hor ? sizes.get(k).h : sizes.get(k).w);
		// lines
		const lines = [];
		if (L.Wraps) {
			let cur = [], used = 0;
			for (const k of items) {
				const m = mainOf(k);
				if (cur.length && used + gap + m > mainAvail + 0.5) { lines.push(cur); cur = []; used = 0; }
				used += (cur.length ? gap : 0) + m;
				cur.push(k);
			}
			if (cur.length) lines.push(cur);
		} else lines.push(items);
		const flex = hor ? L.HorizontalFlex || 'None' : L.VerticalFlex || 'None';
		// grow (Fill / UIFlexItem)
		for (const line of lines) {
			const total = line.reduce((s, k) => s + mainOf(k), 0) + gap * Math.max(0, line.length - 1);
			const free = mainAvail - total;
			const growers = line.filter((k) => flex === 'Fill' || (k.comps.flex && ['Fill', 'Grow', 'Custom'].includes(k.comps.flex.p.FlexMode)));
			if (free > 0.5 && growers.length) {
				const ratios = growers.map((k) => (k.comps.flex && k.comps.flex.p.FlexMode !== 'Fill' ? k.comps.flex.p.GrowRatio || 0 : 1));
				const sum = ratios.reduce((a, b) => a + b, 0) || 1;
				growers.forEach((k, i) => {
					const add = (free * ratios[i]) / sum;
					const s = sizes.get(k);
					const fixed = hor ? { w: s.w / k.s + add / k.s, h: s.h / k.s } : { w: s.w / k.s, h: s.h / k.s + add / k.s };
					sizes.set(k, measure(k, cw, ch, fixed));
				});
			}
		}
		// stretch cross axis
		const lineAlign = L.ItemLineAlignment || 'Automatic';
		// positions
		const crossAlign = hor ? L.VerticalAlignment || 'Top' : L.HorizontalAlignment || 'Left';
		const mainAlign = hor ? L.HorizontalAlignment || 'Left' : L.VerticalAlignment || 'Top';
		const lineCross = lines.map((line) => line.reduce((m, k) => Math.max(m, crossOf(k)), 0));
		const totalCross = lineCross.reduce((s, v) => s + v, 0) + gap * Math.max(0, lines.length - 1);
		let crossCursor = 0;
		if (L.Wraps) {
			if (crossAlign === 'Center') crossCursor = (crossAvail - totalCross) / 2;
			else if (crossAlign === 'Bottom' || crossAlign === 'Right') crossCursor = crossAvail - totalCross;
		}
		let maxMain = 0;
		lines.forEach((line, li) => {
			const n = line.length;
			const total = line.reduce((s, k) => s + mainOf(k), 0) + gap * Math.max(0, n - 1);
			const free = mainAvail - total;
			let start = 0, g = gap;
			if (flex === 'SpaceBetween' && n > 1 && free > 0) g = gap + free / (n - 1);
			else if (flex === 'SpaceEvenly' && free > 0) { start = free / (n + 1); g = gap + free / (n + 1); }
			else if (flex === 'SpaceAround' && free > 0) { start = free / n / 2; g = gap + free / n; }
			else if (mainAlign === 'Center') start = free / 2;
			else if (mainAlign === 'Right' || mainAlign === 'Bottom') start = free;
			let cursor = start;
			for (const k of line) {
				let size = sizes.get(k);
				const lc = L.Wraps ? lineCross[li] : crossAvail;
				let align = lineAlign;
				if (k.comps.flex && k.comps.flex.p.ItemLineAlignment && k.comps.flex.p.ItemLineAlignment !== 'Automatic') align = k.comps.flex.p.ItemLineAlignment;
				if (align === 'Stretch') {
					const fixed = hor ? { w: size.w / k.s, h: lc / k.s } : { w: lc / k.s, h: size.h / k.s };
					size = measure(k, cw, ch, fixed);
					sizes.set(k, size);
				}
				const cs = hor ? size.h : size.w;
				let crossPos;
				const a = align === 'Automatic' ? crossAlign : align;
				if (a === 'Center') crossPos = (lc - cs) / 2;
				else if (a === 'Bottom' || a === 'Right' || a === 'End') crossPos = lc - cs;
				else crossPos = 0;
				if (L.Wraps) crossPos += crossCursor;
				if (hor) { k.x = cursor; k.y = crossPos; } else { k.x = crossPos; k.y = cursor; }
				cursor += (hor ? size.w : size.h) + g;
			}
			maxMain = Math.max(maxMain, total);
			crossCursor += lineCross[li] + gap;
		});
		const contentCross = L.Wraps ? totalCross : lineCross[0] || 0;
		node.listContent = hor ? { w: maxMain, h: contentCross } : { w: contentCross, h: maxMain };
	}
	function layoutGrid(node, kids, cw, ch) {
		const G = node.comps.grid.p;
		const CS = G.CellSize || [0, 100, 0, 100];
		const CP = G.CellPadding || [0, 5, 0, 5];
		let w = CS[0] * cw + CS[1], h = CS[2] * ch + CS[3];
		const gridNode = node.comps.grid;
		if (gridNode.comps && gridNode.comps.aspect) ({ w, h } = constrain(gridNode, w, h));
		const px = CP[0] * cw + CP[1], py = CP[2] * ch + CP[3];
		const items = sortKids(kids, G.SortOrder || 'LayoutOrder');
		const hor = (G.FillDirection || 'Horizontal') === 'Horizontal';
		let per = hor ? Math.floor((cw + px) / (w + px)) : Math.floor((ch + py) / (h + py));
		per = Math.max(1, per);
		if (G.FillDirectionMaxCells > 0) per = Math.min(per, G.FillDirectionMaxCells);
		const n = items.length;
		const cols = hor ? Math.min(n, per) : Math.ceil(n / per);
		const rows = hor ? Math.ceil(n / per) : Math.min(n, per);
		const bw = cols * w + Math.max(0, cols - 1) * px;
		const bh = rows * h + Math.max(0, rows - 1) * py;
		const ha = G.HorizontalAlignment || 'Left', va = G.VerticalAlignment || 'Top';
		const ox = ha === 'Center' ? (cw - bw) / 2 : ha === 'Right' ? cw - bw : 0;
		const oy = va === 'Center' ? (ch - bh) / 2 : va === 'Bottom' ? ch - bh : 0;
		items.forEach((k, i) => {
			const col = hor ? i % per : Math.floor(i / per);
			const row = hor ? Math.floor(i / per) : i % per;
			measure(k, cw, ch, { w, h });
			k.s = scaleOf(k);
			k.x = ox + col * (w + px);
			k.y = oy + row * (h + py);
		});
		node.gridContent = { w: bw, h: bh };
	}

	// ---------------------------------------------------------------------------------------------
	// rendering
	function cornerPx(node, w, h) {
		const c = node.comps.corner;
		if (!c) return 0;
		const r = c.p.CornerRadius || [0, 8];
		const m = Math.min(w, h);
		return clamp(r[0] * m + r[1], 0, m / 2);
	}
	function ringShadows(T, color) {
		const out = [];
		const radii = T > 1.6 ? [T, T * 0.66, T * 0.33] : [T];
		for (const r of radii) {
			const n = Math.max(8, Math.ceil(r * 7));
			for (let i = 0; i < n; i++) {
				const a = (i / n) * Math.PI * 2;
				out.push(`${(Math.cos(a) * r).toFixed(2)}px ${(Math.sin(a) * r).toFixed(2)}px 0 ${color}`);
			}
		}
		return out.join(',');
	}
	function renderBorderStroke(el, node, st, radius) {
		if (st.p.Enabled === false) return;
		const T = st.p.Thickness == null ? 1 : st.p.Thickness;
		if (T <= 0) return;
		const w = node.w, h = node.h;
		const pos = st.p.BorderStrokePosition || 'Outer';
		const off = udim(st.p.BorderOffset, Math.min(w, h));
		let outer;
		if (pos === 'Inner') outer = off;
		else if (pos === 'Center') outer = T / 2 + off;
		else outer = T + off;
		const d = document.createElement('div');
		d.className = 'stroke';
		d.style.left = `${-outer}px`;
		d.style.top = `${-outer}px`;
		d.style.width = `${w + outer * 2}px`;
		d.style.height = `${h + outer * 2}px`;
		let r = 0;
		if (radius > 0) r = radius + outer;
		else if ((st.p.LineJoinMode || 'Round') === 'Round' && outer > 0) r = outer;
		d.style.borderRadius = `${r}px`;
		const color = st.p.Color || [0, 0, 0];
		const alpha = 1 - (st.p.Transparency || 0);
		const g = st.comps.gradient;
		if (g && g.p.Enabled !== false) {
			d.style.padding = `${T}px`;
			d.style.background = cssGradient(g, w + outer * 2, h + outer * 2, color, alpha);
			d.style.webkitMask = 'linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)';
			d.style.webkitMaskComposite = 'xor';
			d.style.maskComposite = 'exclude';
		} else {
			d.style.border = `${T}px solid ${rgba(color, alpha)}`;
		}
		el.appendChild(d);
	}
	function renderText(el, node) {
		const p = node.p;
		const text = visibleText(node);
		if (!text.length) return;
		const pad = node.pad || { l: 0, t: 0, r: 0, b: 0 };
		const box = { x: pad.l, y: pad.t, w: Math.max(0, node.w - pad.l - pad.r), h: Math.max(0, node.h - pad.t - pad.b) };
		const size = textSizeFor(node, box.w, box.h);
		const cf = cssFont(p.FontFace);
		const k = lineFactor(cf);
		const wrap = !!p.TextWrapped;
		const m = measureText(node, size, wrap ? box.w : null);
		const lh = size * (p.LineHeight || 1);
		const ya = p.TextYAlignment || 'Center';
		const xa = p.TextXAlignment || 'Center';
		const blockH = m.lines === 1 ? lh : m.lines * lh;
		const visualH = m.h;
		let y = box.y;
		if (ya === 'Center') y = box.y + (box.h - visualH) / 2;
		else if (ya === 'Bottom') y = box.y + box.h - visualH;
		// CSS centres glyphs inside each line box (half-leading); shift so the first glyph row starts at y
		y -= (lh - size) / 2;
		const truncate = p.TextTruncate && p.TextTruncate !== 'None';
		let x = box.x, width = box.w;
		if (!wrap && !truncate) {
			width = Math.max(m.w, 0) + 2;
			if (xa === 'Center') x = box.x + (box.w - width) / 2;
			else if (xa === 'Right') x = box.x + box.w - width;
		}
		const color = p.TextColor3 || [0, 0, 0];
		const alpha = 1 - (p.TextTransparency || 0);
		const make = () => {
			const d = document.createElement('div');
			d.className = 't';
			d.style.left = `${x}px`;
			d.style.top = `${y}px`;
			d.style.width = `${width}px`;
			d.style.height = `${blockH}px`;
			d.style.fontFamily = cf.family;
			d.style.fontWeight = cf.weight;
			d.style.fontStyle = cf.style;
			d.style.fontSize = `${size / k}px`;
			d.style.lineHeight = `${lh}px`;
			d.style.whiteSpace = wrap ? 'pre-wrap' : 'pre';
			d.style.textAlign = xa === 'Left' ? 'left' : xa === 'Right' ? 'right' : 'center';
			if (truncate) {
				d.style.overflow = 'hidden';
				d.style.textOverflow = 'ellipsis';
				if (wrap) {
					const maxLines = Math.max(1, Math.floor(box.h / lh));
					d.style.display = '-webkit-box';
					d.style.webkitLineClamp = String(maxLines);
					d.style.webkitBoxOrient = 'vertical';
					d.style.height = `${Math.min(blockH, maxLines * lh)}px`;
				}
			}
			if (p.RichText) d.innerHTML = richToHtml(text, cf, k);
			else d.textContent = text;
			return d;
		};
		// strokes behind the fill
		const contextual = node.comps.strokes.filter((s) => (s.p.ApplyStrokeMode || 'Contextual') === 'Contextual' && s.p.Enabled !== false);
		for (const st of contextual) {
			const T = st.p.Thickness == null ? 1 : st.p.Thickness;
			let scol = st.p.Color || [0, 0, 0];
			if (st.comps.gradient) scol = averageColor(st.comps.gradient, scol);
			const d = make();
			d.style.color = 'transparent';
			d.style.textShadow = ringShadows(T, rgba(scol, 1));
			d.style.opacity = String((1 - (st.p.Transparency || 0)) * alpha);
			el.appendChild(d);
		}
		if (p.TextStrokeTransparency != null && p.TextStrokeTransparency < 1) {
			const d = make();
			d.style.color = 'transparent';
			d.style.textShadow = ringShadows(1, rgba(p.TextStrokeColor3 || [0, 0, 0], 1));
			d.style.opacity = String((1 - p.TextStrokeTransparency) * alpha);
			el.appendChild(d);
		}
		const fill = make();
		const g = node.comps.gradient;
		if (g && g.p.Enabled !== false) {
			fill.style.backgroundImage = cssGradient(g, node.w, node.h, color, alpha);
			fill.style.backgroundSize = `${node.w}px ${node.h}px`;
			fill.style.backgroundPosition = `${-x}px ${-y}px`;
			fill.style.webkitBackgroundClip = 'text';
			fill.style.backgroundClip = 'text';
			fill.style.color = 'transparent';
		} else {
			fill.style.color = rgba(color, alpha);
		}
		el.appendChild(fill);
	}
	function render(node, parentEl, rotatedChain) {
		const p = node.p;
		const el = document.createElement('div');
		el.className = 'g';
		if (OPTS.debugNames) el.dataset.name = `${node.cls}:${node.name}`;
		const s = node.s || 1;
		const rot = p.Rotation || 0;
		el.style.left = `${node.x || 0}px`;
		el.style.top = `${node.y || 0}px`;
		el.style.width = `${node.w}px`;
		el.style.height = `${node.h}px`;
		el.style.zIndex = String(p.ZIndex == null ? 1 : p.ZIndex);
		if (rot || s !== 1) {
			const cx = (node.w * s) / 2, cy = (node.h * s) / 2;
			el.style.transformOrigin = '0 0';
			el.style.transform = `translate(${cx}px,${cy}px) rotate(${rot}deg) translate(${-cx}px,${-cy}px) scale(${s})`;
		}
		const radius = cornerPx(node, node.w, node.h);
		if (radius > 0 && node.cls !== 'ScrollingFrame') el.style.borderRadius = `${radius}px`;
		const bgT = p.BackgroundTransparency == null ? 0 : p.BackgroundTransparency;
		if (bgT < 1 && node.cls !== 'ScrollingFrame' || (node.cls === 'ScrollingFrame' && bgT < 1)) {
			const base = p.BackgroundColor3 || [0.64, 0.64, 0.65];
			const g = node.comps.gradient;
			if (g && g.p.Enabled !== false) el.style.backgroundImage = cssGradient(g, node.w, node.h, base, 1 - bgT);
			else el.style.backgroundColor = rgba(base, 1 - bgT);
			if ((p.BorderSizePixel || 0) > 0) el.style.outline = `${p.BorderSizePixel}px solid ${rgba(p.BorderColor3 || [0.1, 0.1, 0.1], 1 - bgT)}`;
		}
		if (node.cls === 'CanvasGroup') el.style.opacity = String(1 - (p.GroupTransparency || 0));
		for (const st of node.comps.strokes) {
			const mode = st.p.ApplyStrokeMode || 'Contextual';
			if (mode === 'Border' || !TEXT.has(node.cls)) renderBorderStroke(el, node, st, radius);
		}
		if (TEXT.has(node.cls)) renderText(el, node);
		if (node.cls === 'ViewportFrame' && OPTS.viewportPlaceholder !== false) {
			const ph = document.createElement('div');
			ph.className = 'vp';
			ph.innerHTML = '<div class="vp-fig"></div><div class="vp-cap">VIEWPORT</div>';
			el.appendChild(ph);
		}
		if ((node.cls === 'ImageLabel' || node.cls === 'ImageButton') && p.Image) {
			const im = document.createElement('div');
			im.className = 'img';
			im.style.background = rgba(p.ImageColor3 || [1, 1, 1], 0.25 * (1 - (p.ImageTransparency || 0)));
			el.appendChild(im);
		}
		const isRot = rotatedChain || rot !== 0;
		const clip = (p.ClipsDescendants || node.cls === 'CanvasGroup' || node.cls === 'ScrollingFrame') && !isRot;
		let host = el;
		if (clip) {
			host = document.createElement('div');
			host.className = 'clip';
			if (node.cls === 'CanvasGroup' && radius > 0) host.style.borderRadius = `${radius}px`;
			el.appendChild(host);
		}
		let inner = host;
		if (node.cls === 'ScrollingFrame' && node.canvas) {
			inner = document.createElement('div');
			inner.className = 'canvas';
			const cp = p.CanvasPosition || [0, 0];
			inner.style.left = `${-cp[0]}px`;
			inner.style.top = `${-cp[1]}px`;
			inner.style.width = `${node.canvas.w}px`;
			inner.style.height = `${node.canvas.h}px`;
			host.appendChild(inner);
		}
		for (const k of visibleKids(node)) render(k, inner, isRot);
		if (node.cls === 'ScrollingFrame' && node.canvas && node.scrollY && node.canvas.thick > 0) {
			const bar = document.createElement('div');
			bar.className = 'sbar';
			const t = node.canvas.thick;
			const frac = node.h / node.canvas.h;
			bar.style.width = `${t}px`;
			bar.style.left = `${node.w - t}px`;
			bar.style.top = '0px';
			bar.style.height = `${Math.max(16, node.h * frac)}px`;
			bar.style.background = rgba(p.ScrollBarImageColor3 || [1, 1, 1], 1 - (p.ScrollBarImageTransparency || 0));
			el.appendChild(bar);
		}
		parentEl.appendChild(el);
	}

	// ---------------------------------------------------------------------------------------------
	function collectFonts(n, set) {
		if (n.props && n.props.FontFace) {
			const cf = cssFont(n.props.FontFace);
			set.add(`${cf.style} ${cf.weight} 24px ${cf.family}`);
		}
		(n.children || []).forEach((c) => collectFonts(c, set));
	}

	window.__render = async function () {
		const doc = window.__GUI__;
		const [VW, VH] = doc.viewport;
		const stage = document.getElementById('stage');
		stage.style.width = `${VW}px`;
		stage.style.height = `${VH}px`;
		measureEl = document.getElementById('measure');
		const fonts = new Set();
		collectFonts(doc.root, fonts);
		await Promise.all([...fonts].map((f) => document.fonts.load(f, 'AaЖж09*').catch(() => null)));
		await document.fonts.ready;
		const root = prep(doc.root, null);
		const inset = root.p.IgnoreGuiInset === false ? 58 : 0;
		root.w = VW;
		root.h = VH - inset;
		root.s = 1;
		layoutInside(root);
		const host = document.createElement('div');
		host.className = 'g';
		host.style.left = '0px';
		host.style.top = `${inset}px`;
		host.style.width = `${VW}px`;
		host.style.height = `${VH - inset}px`;
		for (const k of visibleKids(root)) render(k, host, false);
		stage.appendChild(host);
		return { fonts: [...fonts], elements: document.querySelectorAll('.g').length };
	};
})();

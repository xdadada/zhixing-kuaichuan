#!/usr/bin/env python3
"""从 @iconify-json/solar 生成 SolarIcons.ttf + solar_icons.dart。

Solar bold 变体是纯填充 path,直接转 TrueType 字形。
用法: python3 tool/gen_solar_font.py
输入: build/solar/package/icons.json (npm 缓存解包)
输出: assets/fonts/SolarIcons.ttf, lib/ui/solar_icons.dart
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.misc.transform import Transform
from fontTools.svgLib.path import parse_path


# ---------------------------------------------------------------- even-odd
# SVG 用 evenodd 填充,TrueType 用非零环绕。方向相同的嵌套轮廓在非零下不挖孔。
# 归一化:按嵌套深度调整方向 —— 偶数层顺时针(外形),奇数层逆时针(孔)。

def _contour_points(contour, samples=8):
    """把一条轮廓(RecordingPen value 列表)采样为多边形顶点。"""
    pts = []
    cur = None
    for op, args in contour:
        if op == 'moveTo':
            cur = args[0]
            pts.append(cur)
        elif op == 'lineTo':
            cur = args[0]
            pts.append(cur)
        elif op in ('curveTo', 'qCurveTo'):
            cps = [cur] + [p for p in args if p is not None]
            end = args[-1] if args[-1] is not None else cps[-1]
            for k in range(1, samples + 1):
                t = k / samples
                # de Casteljau 逐层插值,足够作包含测试
                layer = cps
                while len(layer) > 1:
                    layer = [
                        ((1 - t) * a[0] + t * b[0], (1 - t) * a[1] + t * b[1])
                        for a, b in zip(layer, layer[1:])
                    ]
                pts.append(layer[0])
            cur = end
    return pts


def _signed_area(pts):
    s = 0.0
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        s += x1 * y2 - x2 * y1
    return s / 2


def _point_in_poly(pt, poly):
    x, y = pt
    inside = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > y) != (y2 > y):
            xt = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < xt:
                inside = not inside
    return inside


def normalize_even_odd(recording):
    """按 evenodd 语义重排轮廓方向,返回新的 RecordingPen value。"""
    # 拆轮廓
    contours = []
    cur = []
    for op, args in recording.value:
        if op == 'moveTo':
            if cur:
                contours.append(cur)
            cur = [(op, args)]
        elif op in ('closePath', 'endPath'):
            cur.append((op, args))
            contours.append(cur)
            cur = []
        else:
            cur.append((op, args))
    if cur:
        contours.append(cur)

    polys = [_contour_points(c) for c in contours]
    out = []
    for i, contour in enumerate(contours):
        if not polys[i]:
            out.extend(contour)
            continue
        # 嵌套深度 = 包含本轮廓采样点的其他轮廓数(取首点即可,Solar 无相交轮廓)
        depth = sum(
            1 for j, poly in enumerate(polys)
            if j != i and poly and _point_in_poly(polys[i][0], poly))
        area = _signed_area(polys[i])
        clockwise = area < 0
        # 偶数层应为外形(顺时针,TrueType 惯例),奇数层为孔(逆时针)
        want_cw = depth % 2 == 0
        if clockwise != want_cw:
            rp = RecordingPen()
            rev = ReverseContourPen(rp)
            _replay(contour, rev)
            out.extend(rp.value)
        else:
            out.extend(contour)
    result = RecordingPen()
    result.value = out
    return result


def _replay(ops, pen):
    for op, args in ops:
        getattr(pen, op)(*args)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Dart 名 -> Solar 图标名。
# 用户要求:除底部 4 个导航 tab(实心 bold),其余尽量用线性(outline)。
# Solar 的 -outline 变体是填充式轮廓(evenodd),适配填充字形生成。
ICONS = {
    # 导航 tab —— 选中实心 bold,未选中 outline
    'devices': 'devices-bold',
    'devicesOutline': 'devices-outline',
    'history': 'history-2-bold',
    'historyOutline': 'history-2-outline',
    'settings': 'settings-bold',
    'settingsOutline': 'settings-outline',
    # 设备类型
    'laptop': 'laptop-2-outline',
    'phone': 'smartphone-2-outline',
    'desktop': 'monitor-outline',
    'tablet': 'tablet-outline',
    'unknownDevice': 'box-outline',
    'thisDevice': 'user-circle-outline',
    # 网络
    'wifi': 'wi-fi-router-round-outline',
    'router': 'wi-fi-router-outline',
    'globe': 'global-outline',
    'server': 'server-2-outline',
    'port': 'plug-circle-outline',
    'link': 'link-round-outline',
    # 传输方向
    'send': 'inbox-out-outline',
    'receive': 'inbox-in-outline',
    'upload': 'square-arrow-up-outline',
    'download': 'square-arrow-down-outline',
    'transfer': 'transfer-horizontal-outline',
    'swap': 'square-transfer-horizontal-outline',
    # 文件类型
    'fileText': 'document-text-outline',
    'fileImage': 'gallery-outline',
    'fileAudio': 'music-note-3-outline',
    'fileVideo': 'video-frame-outline',
    'fileZip': 'zip-file-outline',
    'file': 'file-outline',
    'folder': 'folder-outline',
    'folderFiles': 'folder-with-files-outline',
    'archive': 'archive-outline',
    # 动作
    'add': 'add-circle-outline',
    'close': 'close-circle-outline',
    'check': 'check-circle-outline',
    'chevronRight': 'alt-arrow-right-outline',
    'chevronDown': 'alt-arrow-down-outline',
    'pause': 'pause-circle-outline',
    'play': 'play-circle-outline',
    'stop': 'stop-circle-outline',
    'refresh': 'refresh-outline',
    'sync': 'refresh-circle-outline',
    'trash': 'trash-bin-trash-outline',
    'copy': 'copy-outline',
    'edit': 'pen-2-outline',
    'search': 'magnifer-outline',
    'more': 'menu-dots-outline',
    'share': 'share-outline',
    'qr': 'qr-code-outline',
    'scan': 'code-scan-outline',
    'eye': 'eye-outline',
    # 状态与设置
    'info': 'info-circle-outline',
    'shield': 'shield-check-outline',
    'lock': 'shield-keyhole-outline',
    'darkMode': 'moon-outline',
    'lightMode': 'sun-outline',
    'starOn': 'star-bold',
    'starOff': 'star-outline',
    'clock': 'clock-circle-outline',
    'timer': 'stopwatch-outline',
    'bolt': 'bolt-outline',
    'rocket': 'rocket-2-outline',
    'tune': 'tuning-2-outline',
    'bell': 'bell-outline',
    'warn': 'danger-triangle-outline',
    'block': 'forbidden-circle-outline',
    'cpu': 'cpu-bolt-outline',
    'done': 'confetti-minimalistic-outline',
    'cat': 'cat-bold',
}

PUA_START = 0xE800


def main():
    icons_json = os.path.join(ROOT, 'build', 'solar', 'package', 'icons.json')
    data = json.load(open(icons_json))
    all_icons = data['icons']
    width_default = data.get('width', 24)
    height_default = data.get('height', 24)

    missing = [v for v in ICONS.values() if v not in all_icons]
    if missing:
        print('MISSING:', missing)
        for m in missing:
            stem = m.rsplit('-bold', 1)[0].split('-outline')[0]
            near = [n for n in all_icons if stem.split('-')[0] in n][:6]
            print('  近似:', m, '->', near)
        sys.exit(1)

    upm = 1000
    glyph_order = ['.notdef']
    cmap = {}
    glyphs = {}
    advances = {}

    pen0 = TTGlyphPen(None)
    glyphs['.notdef'] = pen0.glyph()
    advances['.notdef'] = upm

    # 名称排序保证输出稳定
    for i, (dart_name, icon_name) in enumerate(sorted(ICONS.items())):
        icon = all_icons[icon_name]
        body = icon['body']
        w = icon.get('width', width_default)
        h = icon.get('height', height_default)
        # (?<![\w-]) 防止 id="..." 被当作 d="...";mask 图标取 fill="#fff" 的正形
        # 减去 #000 挖孔 —— TrueType 非零环绕下反向孔洞天然成立,但这里挖孔
        # path 方向与外形一致,简化处理:只保留 #fff 外形 + 单独叠加 #000 形状
        # 会失真,所以干脆展开 mask:白色部分作填充,黑色部分反向。
        # fontTools 无布尔运算,退而求其次:黑色 path 逆向后与白色合并,
        # 依赖非零环绕产生孔洞。Solar 的 mask 图标黑白 path 方向相同,逆向即可。
        if '<mask' in body:
            whites = re.findall(r'<path fill="#fff"[^>]*? d="([^"]+)"', body)
            blacks = re.findall(r'<path fill="#000"[^>]*? d="([^"]+)"', body)
            if not whites:
                whites = re.findall(r'fill="#fff"[^>]*?d="([^"]+)"', body)
                blacks = re.findall(r'fill="#000"[^>]*?d="([^"]+)"', body)
            paths = whites
            reversed_paths = blacks
        else:
            paths = re.findall(r'(?<![\w-])d="([^"]+)"', body)
            reversed_paths = []
        # <circle> 元素转两段圆弧 path
        for m in re.finditer(
                r'<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)"', body):
            cx, cy, r = map(float, m.groups())
            paths.append(
                f'M {cx - r} {cy} '
                f'A {r} {r} 0 1 0 {cx + r} {cy} '
                f'A {r} {r} 0 1 0 {cx - r} {cy} Z')
        if not paths:
            print('no path in', icon_name)
            sys.exit(1)
        gname = 'u%04X' % (PUA_START + i)
        # 1) 先录制原始轮廓(SVG 坐标系)
        rec = RecordingPen()
        for d in paths:
            parse_path(d, rec)
        for d in reversed_paths:
            rp = ReverseContourPen(rec)
            parse_path(d, rp)
        # 2) evenodd → 非零环绕方向归一化(挖孔正确)
        rec = normalize_even_odd(rec)
        # 3) 三次→二次、翻转缩放到 UPM,基线下沉 15%
        pen = TTGlyphPen(None)
        qpen = Cu2QuPen(pen, max_err=upm * 0.002)
        t = Transform(upm / w, 0, 0, -upm / h, 0, upm * 0.85)
        tpen = TransformPen(qpen, t)
        _replay(rec.value, tpen)
        glyphs[gname] = pen.glyph()
        advances[gname] = upm
        glyph_order.append(gname)
        cmap[PUA_START + i] = gname

    fb = FontBuilder(upm, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    metrics = {}
    glyf = fb.font['glyf']
    for gname in glyph_order:
        g = glyf[gname]
        metrics[gname] = (advances[gname], getattr(g, 'xMin', 0) or 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=int(upm * 0.85), descent=-int(upm * 0.15))
    fb.setupNameTable({
        'familyName': 'SolarIcons',
        'styleName': 'Regular',
        'fullName': 'SolarIcons',
        'psName': 'SolarIcons-Regular',
    })
    fb.setupOS2(sTypoAscender=int(upm * 0.85),
                sTypoDescender=-int(upm * 0.15),
                usWinAscent=int(upm * 0.85),
                usWinDescent=int(upm * 0.15))
    fb.setupPost()

    out_font = os.path.join(ROOT, 'assets', 'fonts', 'SolarIcons.ttf')
    os.makedirs(os.path.dirname(out_font), exist_ok=True)
    fb.save(out_font)
    print('wrote', out_font, os.path.getsize(out_font), 'bytes,',
          len(glyph_order) - 1, 'glyphs')

    # Dart 常量类
    lines = [
        "// GENERATED by tool/gen_solar_font.py — do not edit by hand.",
        "// Solar icon set (CC BY 4.0, https://www.figma.com/community/file/1166831539721848736)",
        "import 'package:flutter/widgets.dart';",
        "",
        "class SolarIcons {",
        "  SolarIcons._();",
        "",
        "  static const _family = 'SolarIcons';",
        "",
    ]
    for i, (dart_name, icon_name) in enumerate(sorted(ICONS.items())):
        lines.append("  /// %s" % icon_name)
        lines.append(
            "  static const IconData %s ="
            " IconData(0x%04X, fontFamily: _family);"
            % (dart_name, PUA_START + i))
    lines.append("}")
    out_dart = os.path.join(ROOT, 'lib', 'ui', 'solar_icons.dart')
    open(out_dart, 'w').write('\n'.join(lines) + '\n')
    print('wrote', out_dart)


if __name__ == '__main__':
    main()

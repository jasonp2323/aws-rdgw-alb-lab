#!/usr/bin/env python3
"""
Regenerates the architecture SVGs in this directory.

    python3 docs/diagrams.py

Hand-editing 1000 lines of SVG is miserable, so the diagrams are generated.
Colours follow the AWS Architecture Icons palette: group borders and service
tiles use the same category colours the official icon set does, so the output
reads like a standard AWS architecture diagram.
"""

import html
import os

# ---------------------------------------------------------------- palette ---

NAVY = "#232F3E"   # AWS Cloud boundary
PINK = "#E7157B"   # AWS account boundary / Management & Governance
TEAL = "#00A4A6"   # Region, Availability Zone, private subnet
PURPLE = "#8C4FFF"  # Networking & Content Delivery
GREEN = "#7AA116"  # public subnet
ORANGE = "#ED7100"  # Compute
RED = "#DD344C"    # Security, Identity & Compliance
GRAY = "#7D8998"   # generic / out of scope

FILL_PRIVATE = "#E6F6F6"
FILL_PUBLIC = "#F2F8EC"
FILL_VPC = "#FBF9FF"
FILL_CARD = "#FFFFFF"
INK = "#16191F"
MUTED = "#5A6B7B"

FONT = "'Amazon Ember','Segoe UI','Helvetica Neue',Arial,sans-serif"


def esc(s):
    return html.escape(str(s), quote=True)


# ------------------------------------------------------------------ glyphs ---
# Simplified white pictograms drawn inside a coloured service tile. Geometric
# stand-ins for the official icons, not reproductions of them.

def glyph(kind, cx, cy, s):
    w = "#FFFFFF"
    o = []
    if kind == "directory":            # hierarchy: one node over two
        o.append(f'<rect x="{cx-s*.16:.1f}" y="{cy-s*.42:.1f}" width="{s*.32:.1f}" height="{s*.22:.1f}" rx="2" fill="{w}"/>')
        o.append(f'<rect x="{cx-s*.46:.1f}" y="{cy+s*.16:.1f}" width="{s*.30:.1f}" height="{s*.22:.1f}" rx="2" fill="{w}"/>')
        o.append(f'<rect x="{cx+s*.16:.1f}" y="{cy+s*.16:.1f}" width="{s*.30:.1f}" height="{s*.22:.1f}" rx="2" fill="{w}"/>')
        o.append(f'<path d="M{cx:.1f} {cy-s*.20:.1f} V{cy+s*.02:.1f} M{cx-s*.31:.1f} {cy+s*.16:.1f} V{cy+s*.02:.1f} H{cx+s*.31:.1f} V{cy+s*.16:.1f}" stroke="{w}" stroke-width="{s*.075:.1f}" fill="none" stroke-linecap="round"/>')
    elif kind == "nat":                # two opposing arrows
        o.append(f'<path d="M{cx-s*.40:.1f} {cy-s*.14:.1f} H{cx+s*.24:.1f}" stroke="{w}" stroke-width="{s*.10:.1f}" stroke-linecap="round" fill="none"/>')
        o.append(f'<path d="M{cx+s*.12:.1f} {cy-s*.30:.1f} L{cx+s*.40:.1f} {cy-s*.14:.1f} L{cx+s*.12:.1f} {cy+s*.02:.1f} Z" fill="{w}"/>')
        o.append(f'<path d="M{cx+s*.40:.1f} {cy+s*.20:.1f} H{cx-s*.24:.1f}" stroke="{w}" stroke-width="{s*.10:.1f}" stroke-linecap="round" fill="none"/>')
        o.append(f'<path d="M{cx-s*.12:.1f} {cy+s*.04:.1f} L{cx-s*.40:.1f} {cy+s*.20:.1f} L{cx-s*.12:.1f} {cy+s*.36:.1f} Z" fill="{w}"/>')
    elif kind == "dns":                # globe
        r = s * .36
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{w}" stroke-width="{s*.085:.1f}"/>')
        o.append(f'<path d="M{cx-r:.1f} {cy:.1f} H{cx+r:.1f}" stroke="{w}" stroke-width="{s*.075:.1f}"/>')
        o.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r*.48:.1f}" ry="{r:.1f}" fill="none" stroke="{w}" stroke-width="{s*.075:.1f}"/>')
    elif kind == "tgw":                # diamond hub with four arms
        d = s * .30
        o.append(f'<path d="M{cx:.1f} {cy-d:.1f} L{cx+d:.1f} {cy:.1f} L{cx:.1f} {cy+d:.1f} L{cx-d:.1f} {cy:.1f} Z" fill="{w}"/>')
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            x1, y1 = cx + dx * d * 1.28, cy + dy * d * 1.28
            x2, y2 = cx + dx * d * 1.95, cy + dy * d * 1.95
            o.append(f'<path d="M{x1:.1f} {y1:.1f} L{x2:.1f} {y2:.1f}" stroke="{w}" stroke-width="{s*.085:.1f}" stroke-linecap="round"/>')
    elif kind == "ec2":                # chip
        o.append(f'<rect x="{cx-s*.26:.1f}" y="{cy-s*.26:.1f}" width="{s*.52:.1f}" height="{s*.52:.1f}" rx="{s*.06:.1f}" fill="none" stroke="{w}" stroke-width="{s*.09:.1f}"/>')
        o.append(f'<rect x="{cx-s*.10:.1f}" y="{cy-s*.10:.1f}" width="{s*.20:.1f}" height="{s*.20:.1f}" fill="{w}"/>')
        for i in (-1, 0, 1):
            off = i * s * .17
            o.append(f'<path d="M{cx+off:.1f} {cy-s*.40:.1f} V{cy-s*.26:.1f} M{cx+off:.1f} {cy+s*.26:.1f} V{cy+s*.40:.1f}" stroke="{w}" stroke-width="{s*.07:.1f}" stroke-linecap="round"/>')
            o.append(f'<path d="M{cx-s*.40:.1f} {cy+off:.1f} H{cx-s*.26:.1f} M{cx+s*.26:.1f} {cy+off:.1f} H{cx+s*.40:.1f}" stroke="{w}" stroke-width="{s*.07:.1f}" stroke-linecap="round"/>')
    elif kind == "windows":            # four panes
        g = s * .05
        for dx in (-1, 1):
            for dy in (-1, 1):
                x = cx + (g / 2 if dx > 0 else -s * .34)
                y = cy + (g / 2 if dy > 0 else -s * .34)
                o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{s*.30:.1f}" height="{s*.30:.1f}" rx="1.5" fill="{w}"/>')
    elif kind == "igw":                # gate with vertical arrow
        o.append(f'<rect x="{cx-s*.38:.1f}" y="{cy-s*.12:.1f}" width="{s*.76:.1f}" height="{s*.24:.1f}" rx="{s*.05:.1f}" fill="{w}"/>')
        o.append(f'<path d="M{cx:.1f} {cy-s*.42:.1f} V{cy-s*.16:.1f} M{cx:.1f} {cy+s*.16:.1f} V{cy+s*.42:.1f}" stroke="{w}" stroke-width="{s*.09:.1f}" stroke-linecap="round"/>')
    elif kind == "ram":                # three linked nodes
        pts = [(cx, cy - s * .30), (cx - s * .30, cy + s * .24), (cx + s * .30, cy + s * .24)]
        o.append(f'<path d="M{pts[0][0]:.1f} {pts[0][1]:.1f} L{pts[1][0]:.1f} {pts[1][1]:.1f} L{pts[2][0]:.1f} {pts[2][1]:.1f} Z" fill="none" stroke="{w}" stroke-width="{s*.075:.1f}"/>')
        for px, py in pts:
            o.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{s*.115:.1f}" fill="{w}"/>')
    elif kind == "rtb":                # table
        o.append(f'<rect x="{cx-s*.36:.1f}" y="{cy-s*.32:.1f}" width="{s*.72:.1f}" height="{s*.64:.1f}" rx="{s*.05:.1f}" fill="none" stroke="{w}" stroke-width="{s*.085:.1f}"/>')
        o.append(f'<path d="M{cx-s*.36:.1f} {cy-s*.10:.1f} H{cx+s*.36:.1f} M{cx-s*.36:.1f} {cy+s*.10:.1f} H{cx+s*.36:.1f} M{cx-s*.06:.1f} {cy-s*.32:.1f} V{cy+s*.32:.1f}" stroke="{w}" stroke-width="{s*.06:.1f}"/>')
    elif kind == "ssm":                # gear
        import math
        r_in, r_out = s * .17, s * .34
        pts = []
        for i in range(16):
            a = math.radians(i * 22.5)
            r = r_out if (i % 2 == 0) else r_out * .74
            pts.append(f"{cx+r*math.cos(a):.1f},{cy+r*math.sin(a):.1f}")
        o.append(f'<polygon points="{" ".join(pts)}" fill="{w}"/>')
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r_in:.1f}" fill="none" stroke="{w}" stroke-width="0" />')
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r_in*.72:.1f}" fill="{FILL_CARD}"/>')
    elif kind == "cloud":
        o.append(f'<path d="M{cx-s*.40:.1f} {cy+s*.16:.1f} a{s*.17:.1f} {s*.17:.1f} 0 0 1 {s*.02:.1f} -{s*.33:.1f} a{s*.24:.1f} {s*.24:.1f} 0 0 1 {s*.46:.1f} -{s*.10:.1f} a{s*.19:.1f} {s*.19:.1f} 0 0 1 {s*.32:.1f} {s*.20:.1f} a{s*.15:.1f} {s*.15:.1f} 0 0 1 -{s*.04:.1f} {s*.23:.1f} Z" fill="{w}"/>')
    elif kind == "account":
        o.append(f'<circle cx="{cx:.1f}" cy="{cy-s*.14:.1f}" r="{s*.16:.1f}" fill="{w}"/>')
        o.append(f'<path d="M{cx-s*.30:.1f} {cy+s*.34:.1f} a{s*.30:.1f} {s*.30:.1f} 0 0 1 {s*.60:.1f} 0 Z" fill="{w}"/>')
    elif kind == "vpc":
        o.append(f'<path d="M{cx:.1f} {cy-s*.36:.1f} L{cx+s*.32:.1f} {cy-s*.18:.1f} V{cy+s*.18:.1f} L{cx:.1f} {cy+s*.36:.1f} L{cx-s*.32:.1f} {cy+s*.18:.1f} V{cy-s*.18:.1f} Z" fill="none" stroke="{w}" stroke-width="{s*.09:.1f}"/>')
    return "".join(o)


def tile(x, y, size, color, kind, radius=6):
    """A service icon tile: rounded square in the category colour."""
    return (f'<g><rect x="{x}" y="{y}" width="{size}" height="{size}" rx="{radius}" fill="{color}"/>'
            f'{glyph(kind, x + size/2, y + size/2, size)}</g>')


def text(x, y, s, size=13, color=INK, weight="400", anchor="start", ls="0"):
    return (f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" fill="{color}" '
            f'font-weight="{weight}" text-anchor="{anchor}" letter-spacing="{ls}">{esc(s)}</text>')


def group_box(x, y, w, h, label, color, kind=None, dashed=False, fill="none",
              sublabel=None, opacity=1.0):
    """AWS-style container: coloured border, icon + label in the top-left."""
    dash = ' stroke-dasharray="7 5"' if dashed else ''
    o = [f'<g opacity="{opacity}">',
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" '
         f'stroke="{color}" stroke-width="2"{dash}/>']
    tx = x + 14
    if kind:
        o.append(tile(x + 12, y + 12, 26, color, kind, radius=4))
        tx = x + 46
    o.append(text(tx, y + 25, label, size=13, weight="700", color=color))
    if sublabel:
        o.append(text(tx, y + 40, sublabel, size=11, color=MUTED))
    o.append('</g>')
    return "".join(o)


def card(x, y, w, h, color, kind, title, lines=(), tile_size=34):
    """White card with a service tile on the left and text beside it."""
    o = [f'<g><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{FILL_CARD}" '
         f'stroke="#D5DBDB" stroke-width="1"/>',
         tile(x + 12, y + (h - tile_size) / 2, tile_size, color, kind)]
    tx = x + 12 + tile_size + 12
    n = len(lines)
    ty = y + h / 2 - (n * 13) / 2 + 4 if n else y + h / 2 + 4
    o.append(text(tx, ty, title, size=12.5, weight="700"))
    for i, ln in enumerate(lines):
        o.append(text(tx, ty + 15 + i * 13, ln, size=11, color=MUTED))
    o.append('</g>')
    return "".join(o)


def vcard(x, y, w, h, color, kind, title, lines=(), tile_size=34):
    """Compact card: tile centred on top, caption underneath."""
    cx = x + w / 2
    o = [f'<g><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{FILL_CARD}" '
         f'stroke="#D5DBDB" stroke-width="1"/>',
         tile(cx - tile_size / 2, y + 12, tile_size, color, kind)]
    o.append(text(cx, y + 12 + tile_size + 17, title, size=11.5, weight="700", anchor="middle"))
    for i, ln in enumerate(lines):
        o.append(text(cx, y + 12 + tile_size + 31 + i * 12, ln, size=10, color=MUTED, anchor="middle"))
    o.append('</g>')
    return "".join(o)


def arrow(x1, y1, x2, y2, color=NAVY, dashed=False, width=2, both=False, marker="arrow"):
    dash = ' stroke-dasharray="6 4"' if dashed else ''
    start = f' marker-start="url(#{marker}-start-{color[1:]})"' if both else ''
    return (f'<path d="M{x1} {y1} L{x2} {y2}" stroke="{color}" stroke-width="{width}" '
            f'fill="none"{dash} marker-end="url(#{marker}-{color[1:]})"{start} stroke-linecap="round"/>')


def label_chip(x, y, s, color=NAVY, bg="#FFFFFF", size=10.5, pad=7):
    w = len(s) * size * 0.56 + pad * 2
    return (f'<g><rect x="{x - w/2:.1f}" y="{y - 10}" width="{w:.1f}" height="20" rx="10" '
            f'fill="{bg}" stroke="{color}" stroke-width="1"/>'
            f'{text(x, y + 4, s, size=size, color=color, weight="600", anchor="middle")}</g>')


def defs(colors):
    o = ['<defs>']
    for c in colors:
        cid = c[1:]
        o.append(f'<marker id="arrow-{cid}" viewBox="0 0 10 10" refX="9" refY="5" '
                 f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                 f'<path d="M0 0 L10 5 L0 10 z" fill="{c}"/></marker>')
        o.append(f'<marker id="arrow-start-{cid}" viewBox="0 0 10 10" refX="9" refY="5" '
                 f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                 f'<path d="M0 0 L10 5 L0 10 z" fill="{c}"/></marker>')
    o.append('</defs>')
    return "".join(o)


def svg(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">'
            f'<title>{esc(title)}</title>'
            f'<rect width="{w}" height="{h}" fill="#FFFFFF"/>'
            f'{body}</svg>')


# ------------------------------------------------------------ diagram one ---

def rt_box(x, y, w, h, title, rows, accent=PURPLE, note=None):
    o = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#F6F2FF" '
         f'stroke="{accent}" stroke-width="1.5"/>',
         tile(x + 12, y + 12, 26, accent, "rtb", radius=4),
         text(x + 46, y + 30, title, size=12.5, weight="700", color=accent)]
    for i, r in enumerate(rows):
        o.append(text(x + 14, y + 58 + i * 15, r, size=10.5, color=MUTED))
    if note:
        ny = y + h - 26
        o.append(f'<rect x="{x+12}" y="{ny-13}" width="{w-24}" height="22" rx="11" fill="{accent}"/>')
        o.append(text(x + w / 2, ny + 3, note, size=10.5, color="#FFFFFF", weight="700", anchor="middle"))
    return "".join(o)


def build_high_level():
    W, H = 1280, 752
    o = []

    o.append(defs([NAVY, PURPLE, PINK, GRAY, RED, ORANGE]))
    o.append(text(24, 34, "Identity isolation lab — high level", size=19, weight="700"))
    o.append(text(24, 54, "Identity lives in the network account. The workload account reaches it across a Transit Gateway and never hosts a domain controller.",
                  size=12, color=MUTED))

    # Containers
    o.append(group_box(20, 66, 1240, 574, "AWS Cloud", NAVY, "cloud"))
    o.append(group_box(38, 104, 1204, 518, "Region · us-east-1", TEAL, dashed=True))

    # ---- network account
    o.append(group_box(58, 146, 330, 424, "AWS account · network", PINK, "account",
                       sublabel="172106476397"))
    o.append(group_box(76, 198, 294, 354, "Amazon VPC · 10.20.0.0/16", PURPLE, "vpc", fill=FILL_VPC))
    o.append(card(94, 240, 258, 88, RED, "directory", "AWS Managed Microsoft AD",
                  ["corp.theuptimestudio.co", "Standard · 2 domain controllers"]))
    o.append(card(94, 340, 258, 88, PURPLE, "dns", "Route 53 Resolver",
                  ["inbound + outbound endpoints", "forwards the AD zone"]))
    o.append(card(94, 440, 258, 88, PURPLE, "nat", "NAT gateway",
                  ["single, shared", "egress for every account"]))

    # ---- transit gateway
    o.append(group_box(470, 146, 330, 424, "AWS Transit Gateway", PURPLE, "tgw",
                       sublabel="shared to spokes via AWS RAM", fill="#FCFBFF"))
    o.append(rt_box(492, 266, 286, 124, "shared route table",
                    ["associated · network VPC attachment",
                     "propagated · every attachment",
                     "the network account sees all spokes"]))
    o.append(rt_box(492, 404, 286, 148, "spoke route table",
                    ["associated · every spoke attachment",
                     "propagated · network VPC only",
                     "static · 0.0.0.0/0 → network VPC"],
                    note="no spoke-to-spoke routes"))
    o.append(arrow(635, 392, 635, 402, PURPLE, width=1.5))

    # ---- workload account
    o.append(group_box(882, 146, 340, 240, "AWS account · workload", PINK, "account",
                       sublabel="594775506233"))
    o.append(group_box(900, 194, 304, 174, "Amazon VPC · 10.30.0.0/16", PURPLE, "vpc",
                       fill=FILL_VPC, sublabel="private subnets only · no internet gateway"))
    o.append(card(918, 252, 268, 96, ORANGE, "windows", "Windows Server 2022",
                  ["domain joined via SSM", "Session Manager only · no RDP"]))

    # ---- future spoke
    o.append(group_box(882, 416, 340, 154, "future spoke account", GRAY, "account",
                       dashed=True, opacity=0.6))
    o.append(f'<g opacity="0.6">{text(900, 478, "Add one entry to local.spoke_cidrs and", size=11, color=MUTED)}'
             f'{text(900, 494, "local.spoke_attachment_ids. It inherits the", size=11, color=MUTED)}'
             f'{text(900, 510, "spoke route table — reaching identity and", size=11, color=MUTED)}'
             f'{text(900, 526, "egress, but never the workload VPC.", size=11, color=MUTED)}</g>')

    # ---- attachments
    o.append(arrow(392, 350, 466, 350, PURPLE, width=2.5, both=True))
    o.append(label_chip(429, 328, "attachment", PURPLE))
    o.append(arrow(804, 266, 878, 266, PURPLE, width=2.5, both=True))
    o.append(label_chip(841, 244, "attachment", PURPLE))
    o.append(arrow(804, 493, 878, 493, GRAY, width=2, dashed=True))

    # ---- cross-account sharing band
    o.append(f'<rect x="58" y="582" width="1164" height="34" rx="8" fill="#FDF0F6" '
             f'stroke="{PINK}" stroke-width="1.5" stroke-dasharray="7 5"/>')
    o.append(tile(70, 586, 26, PINK, "ram", radius=4))
    o.append(text(106, 604, "Cross-account sharing, network → workload:", size=11.5, weight="700", color=PINK))
    o.append(text(384, 604,
                  "Transit Gateway (RAM)   ·   Route 53 Resolver rule (RAM)   ·   Managed Microsoft AD (Directory Service handshake)",
                  size=11.5, color=MUTED))

    # ---- legend
    leg = [(PURPLE, "Networking — VPC, Transit Gateway, Route 53"),
           (RED, "Security & Identity — Directory Service, RAM"),
           (ORANGE, "Compute — EC2"),
           (PINK, "AWS account boundary"),
           (TEAL, "Region / Availability Zone")]
    x = 24
    for c, lbl in leg:
        o.append(f'<rect x="{x}" y="{H-40}" width="14" height="14" rx="3" fill="{c}"/>')
        o.append(text(x + 21, H - 29, lbl, size=11, color=MUTED))
        x += 26 + len(lbl) * 6.0 + 26
    return svg(W, H, "".join(o), "Identity isolation lab — high level architecture")




# ------------------------------------------------------------ diagram two ---

def mini_rt(x, y, w, h, title, rows, accent=PURPLE):
    o = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#F6F2FF" '
         f'stroke="{accent}" stroke-width="1.5"/>',
         tile(x + 10, y + 10, 22, accent, "rtb", radius=4),
         text(x + 38, y + 25, title, size=10.5, weight="700", color=accent)]
    for i, r in enumerate(rows):
        o.append(text(x + 11, y + 50 + i * 14, r, size=9.5, color=MUTED))
    return "".join(o)


def badge(cx, cy, n, color=NAVY):
    return (f'<g><circle cx="{cx}" cy="{cy}" r="11" fill="{color}" stroke="#FFFFFF" stroke-width="2"/>'
            f'{text(cx, cy + 4, str(n), size=11.5, color="#FFFFFF", weight="700", anchor="middle")}</g>')


def build_detail():
    W, H = 1420, 1470
    o = [defs([NAVY, PURPLE, PINK, GRAY, RED, ORANGE, GREEN, TEAL])]

    o.append(text(24, 34, "Identity isolation lab — detail", size=19, weight="700"))
    o.append(text(24, 54, "Subnets, route tables, Transit Gateway route-table wiring, and the DNS path from the workload account to the domain controllers.",
                  size=12, color=MUTED))

    o.append(group_box(20, 68, 1380, 1250, "AWS Cloud", NAVY, "cloud"))
    o.append(group_box(38, 106, 1344, 1194, "Region · us-east-1", TEAL, dashed=True))

    # ======================================================= network account
    o.append(group_box(58, 148, 1304, 472, "AWS account · network", PINK, "account",
                       sublabel="172106476397"))
    o.append(group_box(78, 200, 1264, 404, "Amazon VPC · 10.20.0.0/16", PURPLE, "vpc",
                       fill=FILL_VPC, sublabel="DHCP option set → domain controller DNS"))

    # internet gateway straddling the VPC boundary
    o.append(text(356, 174, "Internet gateway", size=11, weight="700", color=PURPLE, anchor="middle"))
    o.append(tile(338, 182, 36, PURPLE, "igw"))

    for i, (ax, azn) in enumerate(((98, "us-east-1a"), (638, "us-east-1b"))):
        o.append(group_box(ax, 250, 520, 338, f"Availability Zone · {azn}", TEAL, dashed=True))
        sx = ax + 16

        # public subnet
        o.append(f'<rect x="{sx}" y="284" width="488" height="100" rx="6" fill="{FILL_PUBLIC}" '
                 f'stroke="{GREEN}" stroke-width="1.5"/>')
        pub_cidr = "10.20.32.0/20" if i == 0 else "10.20.48.0/20"
        o.append(text(sx + 14, 303, f"Public subnet · {pub_cidr}", size=11, weight="700", color=GREEN))
        if i == 0:
            o.append(card(sx + 14, 312, 456, 62, PURPLE, "nat", "NAT gateway",
                          ["single, shared — the only path to the internet"]))
        else:
            o.append(text(sx + 244, 348, "reserved — no NAT in this AZ", size=11, color=MUTED, anchor="middle"))

        # private subnet
        o.append(f'<rect x="{sx}" y="398" width="488" height="176" rx="6" fill="{FILL_PRIVATE}" '
                 f'stroke="{TEAL}" stroke-width="1.5"/>')
        priv_cidr = "10.20.0.0/20" if i == 0 else "10.20.16.0/20"
        o.append(text(sx + 14, 417, f"Private subnet · {priv_cidr}", size=11, weight="700", color=TEAL))
        dc = "DC 1" if i == 0 else "DC 2"
        rk = ("Resolver inbound", "queries from spokes") if i == 0 else ("Resolver outbound", "forwards the AD zone")
        o.append(vcard(sx + 14, 430, 144, 112, RED, "directory", dc, ["Managed", "Microsoft AD"]))
        o.append(vcard(sx + 176, 430, 144, 112, PURPLE, "dns", rk[0], [rk[1]]))
        o.append(vcard(sx + 338, 430, 144, 112, PURPLE, "tgw", "TGW", ["attachment ENI"]))

    # NAT -> IGW
    o.append(arrow(356, 312, 356, 222, PURPLE, width=2))

    # route tables
    o.append(text(1178, 272, "Route tables", size=11.5, weight="700", color=MUTED))
    o.append(mini_rt(1178, 284, 146, 100, "public", ["0.0.0.0/0 → IGW", "10.0.0.0/8 → TGW"]))
    o.append(mini_rt(1178, 398, 146, 176, "private", ["0.0.0.0/0 → NAT", "10.0.0.0/8 → TGW",
                                                      "", "one table —", "single NAT gateway"]))

    # ======================================================= transit gateway
    o.append(arrow(620, 620, 620, 662, PURPLE, width=3, both=True))
    o.append(label_chip(880, 641, "network VPC attachment · associated with the shared table", PURPLE))

    o.append(group_box(380, 664, 660, 272, "AWS Transit Gateway", PURPLE, "tgw",
                       sublabel="default association and propagation both disabled", fill="#FCFBFF"))
    o.append(rt_box(404, 722, 300, 196, "shared route table",
                    ["associated · network VPC attachment",
                     "propagated · every attachment",
                     "",
                     "10.20.0.0/16 → network VPC",
                     "10.30.0.0/16 → workload VPC"]))
    o.append(rt_box(716, 722, 300, 196, "spoke route table",
                    ["associated · every spoke attachment",
                     "propagated · network VPC only",
                     "",
                     "10.20.0.0/16 → network VPC",
                     "0.0.0.0/0     → network VPC"],
                    note="no spoke-to-spoke routes"))

    o.append(arrow(1040, 800, 1100, 800, GRAY, dashed=True, width=1.5))
    o.append(text(1108, 794, "a second spoke associates", size=10.5, color=MUTED))
    o.append(text(1108, 808, "with the same spoke table", size=10.5, color=MUTED))

    o.append(arrow(620, 936, 620, 978, PURPLE, width=3, both=True))
    o.append(label_chip(880, 957, "workload VPC attachment · accepted in the network account", PURPLE))

    # ====================================================== workload account
    o.append(group_box(58, 980, 1304, 310, "AWS account · workload", PINK, "account",
                       sublabel="594775506233"))
    o.append(group_box(78, 1024, 1264, 238, "Amazon VPC · 10.30.0.0/16", PURPLE, "vpc",
                       fill=FILL_VPC, sublabel="private subnets only · no internet gateway · no NAT"))

    o.append(card(720, 1030, 260, 42, PURPLE, "dns", "Route 53 Resolver rule (shared)", []))
    o.append(card(1000, 1030, 280, 42, PINK, "ssm", "SSM seamless domain join", []))

    for i, (ax, azn) in enumerate(((98, "us-east-1a"), (638, "us-east-1b"))):
        o.append(group_box(ax, 1078, 520, 166, f"Availability Zone · {azn}", TEAL, dashed=True))
        sx = ax + 16
        o.append(f'<rect x="{sx}" y="1108" width="488" height="120" rx="6" fill="{FILL_PRIVATE}" '
                 f'stroke="{TEAL}" stroke-width="1.5"/>')
        priv_cidr = "10.30.0.0/20" if i == 0 else "10.30.16.0/20"
        o.append(text(sx + 14, 1127, f"Private subnet · {priv_cidr}", size=11, weight="700", color=TEAL))
        if i == 0:
            o.append(card(sx + 14, 1136, 224, 80, ORANGE, "windows", "Windows Server 2022",
                          ["domain joined via SSM", "no key pair · no ingress"]))
            o.append(card(sx + 254, 1136, 216, 80, PURPLE, "tgw", "TGW", ["attachment ENI"]))
        else:
            o.append(card(sx + 14, 1136, 216, 80, PURPLE, "tgw", "TGW", ["attachment ENI"]))
            o.append(text(sx + 360, 1181, "second AZ — attachment ENI only", size=11, color=MUTED, anchor="middle"))

    o.append(text(1178, 1100, "Route tables", size=11.5, weight="700", color=MUTED))
    o.append(mini_rt(1178, 1112, 146, 116, "private × 2", ["0.0.0.0/0 → TGW", "", "one table per AZ —", "egress is remote"]))

    # numbered flow badges
    o.append(badge(352, 1136, 1))   # the instance
    o.append(badge(980, 1030, 2))   # the shared resolver rule, associated with this VPC
    o.append(badge(1016, 722, 3))   # spoke route table
    o.append(badge(974, 430, 4))    # outbound endpoint
    o.append(badge(812, 430, 5))    # domain controllers

    # ============================================================== bottom ---
    o.append(text(24, 1352, "Resolving corp.theuptimestudio.co from the workload account", size=13, weight="700"))
    flows = [
        (1, "The instance asks the Amazon resolver at 10.30.0.2 — the workload VPC keeps the default DNS server."),
        (2, "A Route 53 Resolver rule, shared by RAM and associated with this VPC, matches the AD zone."),
        (3, "Traffic crosses the Transit Gateway on the spoke route table."),
        (4, "The rule's outbound endpoint, in the network VPC, forwards the query onward."),
        (5, "The domain controllers answer. Everything else resolves normally through the Amazon resolver."),
    ]
    for i, (n, txt) in enumerate(flows):
        y = 1378 + i * 19
        o.append(badge(34, y - 4, n))
        o.append(text(54, y, txt, size=11, color=MUTED))

    o.append(text(760, 1352, "Cross-account sharing", size=13, weight="700"))
    shares = [
        (PURPLE, "Transit Gateway", "AWS RAM · organization share, auto-accepted"),
        (PURPLE, "Route 53 Resolver rule", "AWS RAM · associated with the workload VPC"),
        (RED, "AWS Managed Microsoft AD", "Directory Service handshake + accepter"),
    ]
    for i, (c, name, how) in enumerate(shares):
        y = 1378 + i * 19
        o.append(f'<rect x="762" y="{y-11}" width="13" height="13" rx="3" fill="{c}"/>')
        o.append(text(782, y, name, size=11, weight="700"))
        o.append(text(952, y, how, size=11, color=MUTED))
    o.append(text(782, 1378 + 3 * 19 + 4, "Directory security group opened to each spoke CIDR on the AD ports only — no RDP, no SSH.",
                  size=10.5, color=MUTED))

    return svg(W, H, "".join(o), "Identity isolation lab — detailed architecture")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    for fn, builder in (("architecture-high-level.svg", build_high_level),
                        ("architecture-detail.svg", build_detail)):
        path = os.path.join(here, fn)
        open(path, "w").write(builder())
        print("wrote", path)

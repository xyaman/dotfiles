from libqtile.config import Key, Screen, Group, Drag, Click
from libqtile.lazy import lazy
from libqtile import layout, bar, widget, hook

from typing import List
import subprocess

# My imports
import theme

mod = "mod1"
terminal = "termite"

@hook.subscribe.startup_once
def autostart():

    commands = [
        ["nitrogen", "--restore"],
        ["picom", "-b"],
        ["light-locker"],
        ["redshift-gtk"]
    ]

    for cmd in commands: subprocess.Popen(cmd)

keys = [
    # Switch between windows in current stack pane
    Key([mod], "k", lazy.layout.down()),
    Key([mod], "j", lazy.layout.up()),

    # Move windows up or down in current stack
    Key([mod, "control"], "k", lazy.layout.shuffle_down()),
    Key([mod, "control"], "j", lazy.layout.shuffle_up()),

    # Switch window focus to other pane(s) of stack
    Key([mod], "space", lazy.layout.next()),

    # Swap panes of split stack
    Key([mod, "shift"], "space", lazy.layout.rotate()),

    # Swap window to float
    Key([mod, "shift"], "f", lazy.window.toggle_floating()),

    # Toggle between split and unsplit sides of stack.
    # Split = all windows displayed
    # Unsplit = 1 window displayed, like Max layout, but still with
    # multiple stack panes
    Key([mod, "shift"], "Return", lazy.layout.toggle_split()),
    Key([mod], "Return", lazy.spawn(terminal)),

    # Toggle between different layouts as defined below
    Key([mod], "Tab", lazy.next_layout()),
    Key([mod, "shift"], "w", lazy.window.kill()),

    Key([mod, "control"], "r", lazy.restart()),
    Key([mod, "control"], "q", lazy.shutdown()),
    Key([mod], "d", lazy.spawn("dmenu_run")),
]

groups = [Group(i) for i in "123456789"]

# for each group add key bindings
for i in groups:
    keys.extend([
        Key([mod], i.name, lazy.group[i.name].toscreen()),
        Key([mod, "shift"], i.name, lazy.window.togroup(i.name, switch_group=False)),
         # switch_group = True, changes to the new window group
    ])

layouts = [
    layout.MonadTall(**theme.layout),
    layout.MonadWide(**theme.layout),
    layout.Max(),
]

widget_defaults = dict(
    font='Ubuntu Mono',
    fontsize=15,
    padding=5,
    margin=50
)
extension_defaults = widget_defaults.copy()

colors_left = {
    "background": theme.cblack,
}

colors_right = {
    "background": theme.cpurple
}

sep_right = {
    "background": theme.cpurple,
    "foreground": theme.cblack,
    "padding": 15
}

screens = [
    Screen(
        top=bar.Bar(
            [
                widget.CurrentLayout(**colors_left),
                widget.GroupBox(highlight_color=theme.cpurple, this_current_screen_border=theme.cpurple, highlight_method="line",**colors_left),
                widget.WindowName(**colors_left),
                widget.TextBox(background=colors_left["background"], foreground=colors_right["background"], text="", fontsize=57, padding=0),
                widget.Volume(**colors_right, fmt=" {}"),
                widget.Sep(**sep_right),
                widget.Wlan(interface="wlp2s0" , fmt=" {}", format="{essid}", **colors_right),
                widget.Sep(**sep_right),
                widget.Memory(fmt="  {}", **colors_right),
                widget.Sep(**sep_right),
                widget.Pacman(fmt="Updates: {}", **colors_right),
                widget.Sep(**sep_right),
                widget.Battery(format=" {percent: 2.0%}", **colors_right),
                widget.Sep(**sep_right),
                widget.Systray(**colors_right),
                widget.Sep(**sep_right),
                widget.Clock(format='  %A %d - %H:%M ', **colors_right),
            ],
            30,
        ),
    ),
]

# Drag floating layouts.
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(),
         start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(),
         start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front())
]

dgroups_key_binder = None
dgroups_app_rules = []  # type: List
main = None
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(float_rules=[
    # Run the utility of `xprop` to see the wm class and name of an X client.
    {'wmclass': 'confirm'},
    {'wmclass': 'dialog'},
    {'wmclass': 'download'},
    {'wmclass': 'error'},
    {'wmclass': 'file_progress'},
    {'wmclass': 'notification'},
    {'wmclass': 'splash'},
    {'wmclass': 'toolbar'},
    {'wmclass': 'confirmreset'},  # gitk
    {'wmclass': 'makebranch'},  # gitk
    {'wmclass': 'maketag'},  # gitk
    {'wname'  : 'branchdialog'},  # gitk
    {'wname'  : 'pinentry'},  # GPG key password entry
    {'wmclass': 'ssh-askpass'}, # ssh-askpass
    {'wmclass': 'lxappearance'},
    {'wmclass': 'pavucontrol'},
    {'wname' : 'Discord Updater'}
])
auto_fullscreen = True
focus_on_window_activation = "smart"

wmname = "LG3D"

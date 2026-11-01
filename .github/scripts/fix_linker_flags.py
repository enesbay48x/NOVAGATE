import re
import sys

p = "build/NOVAGATE.xcodeproj/project.pbxproj"
try:
    s = open(p).read()
except FileNotFoundError:
    print("pbxproj not found at", p)
    sys.exit(1)

flags = "-framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreAudio -undefined dynamic_lookup"
replacement = 'OTHER_LDFLAGS = "' + flags + '";'

if "OTHER_LDFLAGS" in s:
    count = len(re.findall(r'OTHER_LDFLAGS = [^;]*;', s))
    s = re.sub(r'OTHER_LDFLAGS = [^;]*;', replacement, s)
    print("Updated %d OTHER_LDFLAGS entries" % count)
else:
    count = len(re.findall(r'buildSettings = \{', s))
    s = re.sub(r'(buildSettings = \{)', lambda m: m.group(1) + "\n\t\tOTHER_LDFLAGS = " + '"' + flags + '";', s, count=count)
    print("Added OTHER_LDFLAGS to %d buildSettings blocks" % count)

open(p, "w").write(s)
print("OTHER_LDFLAGS patched in", p)

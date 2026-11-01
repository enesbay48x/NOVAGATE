import re
import sys

p = "build/NOVAGATE.xcodeproj/project.pbxproj"
try:
    s = open(p).read()
except FileNotFoundError:
    print("pbxproj not found at", p)
    sys.exit(1)

flags = "-framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreAudio"

if "OTHER_LDFLAGS" in s:
    s = re.sub(r'OTHER_LDFLAGS = [^;]*;', 'OTHER_LDFLAGS = "%s";' % flags, s)
else:
    s = re.sub(r'(buildSettings = \{)', r'\1\n\t\tOTHER_LDFLAGS = "%s";' % flags, s)

open(p, "w").write(s)
print("OTHER_LDFLAGS patched in", p)

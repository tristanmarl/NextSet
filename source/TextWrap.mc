import Toybox.Graphics;
import Toybox.Lang;

// Measures text for TextWrap; the watch uses a Dc and font, tests a fixed width per character.
class DcMeasure {
    private var _dc as Dc;
    private var _font as Graphics.FontType;

    public function initialize(dc as Dc, font as Graphics.FontType) {
        _dc = dc;
        _font = font;
    }

    public function width(text as String) as Number {
        return _dc.getTextWidthInPixels(text, _font);
    }
}

module TextWrap {
    // Greedy word wrap. Words wider than maxWidth are split by characters. Never drops text.
    function breakLines(value as String, measure as Object, maxWidth as Numeric) as Array {
        var lines = [] as Array<String>;
        var line = "";
        var word = "";
        var count = value.length();
        for (var i = 0; i <= count; i++) {
            var ch = i < count ? value.substring(i, i + 1) : " ";
            if (!Model.sameString(ch, " ")) {
                word = word + ch;
                continue;
            }
            if (word.length() == 0) {
                continue;
            }
            var candidate = line.length() == 0 ? word : line + " " + word;
            if ((measure as DcMeasure).width(candidate) <= maxWidth) {
                line = candidate;
                word = "";
                continue;
            }
            if (line.length() > 0) {
                lines.add(line);
                line = "";
            }
            // The word now starts an empty line; split it while it is too wide.
            while (word.length() > 1 && (measure as DcMeasure).width(word) > maxWidth) {
                var cut = word.length() - 1;
                while (cut > 1 && (measure as DcMeasure).width(word.substring(0, cut)) > maxWidth) {
                    cut--;
                }
                lines.add(word.substring(0, cut));
                word = word.substring(cut, word.length());
            }
            line = word;
            word = "";
        }
        if (line.length() > 0) {
            lines.add(line);
        }
        return lines;
    }

    // First visible line for a scroll step, clamped so the last page stays full.
    function clampTop(top as Number, lineCount as Number, visible as Number) as Number {
        var maxTop = lineCount - visible;
        if (maxTop < 0) {
            maxTop = 0;
        }
        return top < 0 ? 0 : (top > maxTop ? maxTop : top);
    }
}

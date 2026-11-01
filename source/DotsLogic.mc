import Toybox.Lang;

// Pure layout rules of the set-progress dots row, unit-tested in tests/. One row for the whole
// exercise: first one dot per warmup (smaller, gray), then one dot per working set.
module DotsLogic {
    const WARM_DONE = 0;
    const WARM_CURRENT = 1;
    const WARM_OPEN = 2;
    const SET_DONE = 3;
    const SET_CURRENT = 4;
    const SET_OPEN = 5;

    // The current dot's ring reaches this far beyond a working dot's radius; neighbours keep at
    // least MIN_GAP pixels between their edges so a ring never touches them.
    const RING = 3;
    const MIN_GAP = 4;
    const MIN_RADIUS = 3;

    // Dot kinds in screen order. `current` is the slot that is up next (a warmup is
    // Model.WARMUP_BASE + i, a working set its index) or -1 when none is.
    function kinds(warmups as Number, doneWarmups as Number, planned as Number, doneSets as Number,
                   current as Number) as Array<Number> {
        var result = [] as Array<Number>;
        for (var i = 0; i < warmups; i++) {
            if (current == Model.WARMUP_BASE + i) {
                result.add(WARM_CURRENT);
            } else if (i < doneWarmups) {
                result.add(WARM_DONE);
            } else {
                result.add(WARM_OPEN);
            }
        }
        for (var i = 0; i < planned; i++) {
            if (i == current) {
                result.add(SET_CURRENT);
            } else if (i < doneSets) {
                result.add(SET_DONE);
            } else {
                result.add(SET_OPEN);
            }
        }
        return result;
    }

    // Warmup dots are smaller than working dots.
    function warmRadius(radius as Number) as Number {
        var small = radius * 2 / 3;
        return small < 2 ? 2 : small;
    }

    // Sizes for a row that must fit `avail` pixels: working radius, warmup radius, gap between
    // dot edges and the resulting width. Starts from the full size with a gap of one radius and
    // first shrinks the gap (down to MIN_GAP), then the dots (down to MIN_RADIUS).
    function layout(warmups as Number, planned as Number, avail as Number, baseRadius as Number)
            as Dictionary<String, Number> {
        var count = warmups + planned;
        var radius = baseRadius < MIN_RADIUS ? MIN_RADIUS : baseRadius;
        var gap = MIN_GAP;
        var width = 0;
        while (true) {
            var small = warmRadius(radius);
            var dots = 2 * (warmups * small + planned * radius) + 2 * RING;
            var room = count > 1 ? (avail - dots) / (count - 1) : radius;
            var wide = radius < MIN_GAP ? MIN_GAP : radius;
            gap = room > wide ? wide : room;
            width = dots + (count > 1 ? (count - 1) * gap : 0) - 2 * RING;
            if (gap >= MIN_GAP || radius <= MIN_RADIUS) {
                break;
            }
            radius--;
        }
        if (gap < 1) {
            // No room even at the smallest size: draw it anyway, never with a negative width.
            gap = 1;
            var tiny = warmRadius(radius);
            width = 2 * (warmups * tiny + planned * radius) + (count > 1 ? (count - 1) * gap : 0);
        }
        return {"radius" => radius, "warmRadius" => warmRadius(radius), "gap" => gap, "width" => width};
    }
}

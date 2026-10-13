// helpers.c - a second translation unit, so linking more than one object is
// exercised too.

struct point {
    int x, y;
};

int combine(struct point p) {
    return p.x * p.x + p.y * p.y;
}
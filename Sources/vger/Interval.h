// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef Interval_h
#define Interval_h

struct Interval {

    float a;
    float b;

    Interval() : a(0), b(0) { }
    Interval(float a, float b) : a(a), b(b) { }

    bool empty() const { return a > b; }

    bool intersects(Interval I) const
    {
        return b > I.a and a < I.b;
    }

};

#endif /* Interval_h */

"""Wavers University — Portfolio 2: expected results for the seed, computed without SQL.

The five queries are checked against this independent calculation, so a
mistake in the SQL views cannot hide by agreeing with itself. It prints the
exact output psql gives for Olayinka_Egbedokun_queries.sql in unaligned
mode (-A -t -F '|'); the result is saved as
evidence/Olayinka_Egbedokun_seed_expected.txt and compared line by line.

Run: python3 portfolio-2-query-optimisation/Olayinka_Egbedokun_seed_oracle.py
"""
from decimal import Decimal, ROUND_HALF_UP

COURSES = {  # code: (title, units, term)
    "CSC101": ("Introduction to Computing", 3, "first"),
    "CSC103": ("Computing Laboratory", 2, "first"),
    "MTH101": ("Elementary Mathematics I", 3, "first"),
    "PHY101": ("General Physics I", 3, "first"),
    "CHM101": ("General Chemistry I", 2, "first"),
    "CSC102": ("Introduction to Programming", 3, "second"),
    "MTH102": ("Elementary Mathematics II", 3, "second"),
}
ORDER = ["CSC101", "CSC103", "MTH101", "PHY101", "CHM101", "CSC102", "MTH102"]
STUDENTS = {  # matric: (first, last, scores in ORDER)
    "WU/2023/0001": ("Amaka", "Nwosu", ["75", "68", "81", "72", "90", "77", "70"]),
    "WU/2023/0002": ("Tunde", "Bakare", ["55", "61", "49.5", "58", "44", "62", "51"]),
    "WU/2023/0003": ("Zainab", "Bello", ["39.99", "45", "40", "30", "50", "35", "42"]),
    "WU/2023/0004": ("Kelechi", "Obi", ["70", "69.99", "60", "59.99", "45", "49.99", "50"]),
    "WU/2023/0005": ("Ngozi", "Eze", ["20", "38", "41", "10", "44.99", "25", "39.99"]),
    "WU/2023/0006": ("Yusuf", "Lawal", ["88", "92", "79", "85", "66", "0", "100"]),
}
AMENDED = {("WU/2023/0003", "PHY101"): "52"}  # the one correction in the seed
SESSION = "2023/2024"


def grade(score):
    """The Nigerian five-point scale: (letter, points)."""
    for floor, letter, points in [(70, "A", 5), (60, "B", 4), (50, "C", 3), (45, "D", 2), (40, "E", 1)]:
        if score >= floor:
            return letter, points
    return "F", 0


def two(x):
    return x.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def effective(matric, code):
    raw = Decimal(STUDENTS[matric][2][ORDER.index(code)])
    return Decimal(AMENDED.get((matric, code), raw)), (matric, code) in AMENDED


def gpa(matric, codes):
    units = sum(COURSES[c][1] for c in codes)
    points = sum(grade(effective(matric, c)[0])[1] * COURSES[c][1] for c in codes)
    passed = sum(COURSES[c][1] for c in codes if grade(effective(matric, c)[0])[1] > 0)
    return units, passed, two(Decimal(points) / Decimal(units))


def tf(b):
    return "t" if b else "f"


def name(m):
    return f"{STUDENTS[m][1]}, {STUDENTS[m][0]}"


matric, offered = "WU/2023/0003", "PHY101"  # the defaults in queries.sql
first = [c for c in ORDER if COURSES[c][2] == "first"]
second = [c for c in ORDER if COURSES[c][2] == "second"]
cgpa = {m: gpa(m, ORDER) for m in STUDENTS}

print("=== Q1. Transcript of one student")
for term, codes in (("first", first), ("second", second)):
    for c in sorted(codes):
        s, amended = effective(matric, c)
        g, p = grade(s)
        print(f"{SESSION}|{term}|{c}|{COURSES[c][0]}|{COURSES[c][1]}|{two(s)}|{g}|{p}|{tf(amended)}")

print("=== Q2. Semester GPA and CGPA of one student")
for term, codes in (("first", first), ("second", second)):
    units, passed, g = gpa(matric, codes)
    print(f"{SESSION}|{term}|{units}|{passed}|{g}|{cgpa[matric][2]}")

print("=== Q3. Result sheet of one course offering (every registered student)")
for m in sorted(STUDENTS):
    s, amended = effective(m, offered)
    print(f"{m}|{name(m)}|{two(s)}|{grade(s)[0]}|approved|{tf(amended)}")

print("=== Q4. Dean's list: top 10 CGPAs in one programme")
for m in sorted(STUDENTS, key=lambda m: (-cgpa[m][2], m))[:10]:
    print(f"{m}|{name(m)}|{cgpa[m][0]}|{cgpa[m][2]}")

print("=== Q5. Probation list: every student with CGPA below 1.50")
for m in sorted((m for m in STUDENTS if cgpa[m][2] < Decimal("1.50")), key=lambda m: (cgpa[m][2], m)):
    print(f"{m}|CSC-BSC|{cgpa[m][0]}|{cgpa[m][2]}")

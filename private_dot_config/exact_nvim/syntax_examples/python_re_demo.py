import re

re_test: re.Pattern[str] = re.compile(r"^(?P<year>\d{4}) (?P<day>\d) \w\s{,3}")
re_test: re.Pattern[str] = re.compile(
    #
    r"^(?P<year>\d{4}) "
    #
    r"(?P<day>\d) \w\s{,3}"
)

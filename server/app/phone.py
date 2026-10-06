import phonenumbers


def to_e164(number: str, region: str | None) -> str | None:
    """Normalise to E.164, or None if it is not a plausible phone number.

    `region` (ISO 3166-1 alpha-2, e.g. "RO") is used for numbers written
    without a country code, which is how most contacts are stored.
    """
    try:
        parsed = phonenumbers.parse(number, region.upper() if region else None)
    except phonenumbers.NumberParseException:
        return None
    if not phonenumbers.is_possible_number(parsed):
        return None
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)

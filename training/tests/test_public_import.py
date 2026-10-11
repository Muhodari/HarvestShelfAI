from tools.public_experiment import is_augmented, parse_folder, session_of


def test_parse_folder():
    assert parse_folder("Semi fresh Tomato(10-24)") == ("semi", "tomato")
    assert parse_folder("Semi_Fresh eggplant(4-8)") == ("semi", "eggplant")
    assert parse_folder("Rotten banana(7-13)") == ("rotten", "banana")
    assert parse_folder("Semi Fresh Bittermelon ( 3-5)") == ("semi", "bittermelon")


def test_augmented_copies_are_detected():
    assert is_augmented("aug_44_IMG_20251118_170507501_HDR.jpg")
    assert is_augmented("aug_3_Banana (12).jpeg")
    assert not is_augmented("IMG_20251118_170507501_HDR.jpg")


def test_sessions():
    assert session_of("tomato_semi", "IMG_20251118_170507501_HDR.jpg") == "tomato_semi_20251118_17"
    assert session_of("tomato_semi", "IMG_20251118_175959000_HDR.jpg") == "tomato_semi_20251118_17"
    assert session_of("tomato_rotten", "IMG-20260207-WA0001.jpg") == "tomato_rotten_20260207_wa"
    assert session_of("banana_fresh", "Banana (10).jpeg") == "banana_fresh_misc"

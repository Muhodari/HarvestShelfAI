import io

import pytest
import yaml
from PIL import Image

from portal import dataset
from portal.app import create_app
from src.config import DEFAULT_CONFIG, Config


@pytest.fixture
def cfg(tmp_path):
    raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
    raw["paths"] = {**raw["paths"], "raw_dir": "raw", "metadata": "metadata.csv"}
    (tmp_path / "config.yaml").write_text(yaml.safe_dump(raw))
    return Config(tmp_path / "config.yaml")


def jpg() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (40, 30), (200, 60, 40)).save(buf, "JPEG")
    return buf.getvalue()


def fields(**kw) -> dataset.PhotoFields:
    base = dict(crop="tomato", label="fresh", market="kamembe", district="rusizi",
                date="2026-11-03", phone_model="Tecno", batch_id="kamembe_2026-11-03_s01")
    return dataset.PhotoFields(**{**base, **kw})


def test_upload_follows_collection_protocol(cfg):
    rows = dataset.add_photos(cfg, [("a.JPEG", jpg()), ("b.jpg", jpg())], fields())
    assert [r["image_id"] for r in rows] == ["T0001", "T0002"]
    assert rows[0]["file"] == "2026-11-03_kamembe/T0001.jpg"
    assert (cfg.path_of("raw_dir") / rows[1]["file"]).exists()
    df = dataset.read_metadata(cfg)
    assert list(df.columns) == dataset.COLUMNS
    assert df.label_a.tolist() == ["fresh", "fresh"]

    more = dataset.add_photos(cfg, [("c.png", jpg())], fields(crop="banana", label="sell_soon"))
    assert more[0]["image_id"] == "B0001"
    assert dataset.add_photos(cfg, [("d.jpg", jpg())], fields())[0]["image_id"] == "T0003"


@pytest.mark.parametrize("bad, msg", [
    (dict(crop="mango"), "crop"),
    (dict(label="ripe"), "label"),
    (dict(crop="other", label="fresh"), "unusable"),
    (dict(market="Kamembe Market"), "market"),
    (dict(date="03/11/2026"), "date"),
])
def test_upload_rejects_bad_fields(cfg, bad, msg):
    with pytest.raises(dataset.UploadError, match=msg):
        dataset.add_photos(cfg, [("a.jpg", jpg())], fields(**bad))
    assert len(dataset.read_metadata(cfg)) == 0


def test_upload_rejects_non_images_and_saves_nothing(cfg):
    with pytest.raises(dataset.UploadError, match="not a readable image"):
        dataset.add_photos(cfg, [("a.jpg", jpg()), ("b.jpg", b"not an image")], fields())
    assert len(dataset.read_metadata(cfg)) == 0
    assert not cfg.path_of("raw_dir").exists() or not any(cfg.path_of("raw_dir").rglob("*.jpg"))


def test_second_label_disagreement_and_delete(cfg):
    dataset.add_photos(cfg, [("a.jpg", jpg()), ("b.jpg", jpg())], fields())
    dataset.update_photo(cfg, "T0001", {"label_b": "sell_soon"})
    s = dataset.summary(cfg)
    assert s["double_labelled"] == 1 and s["disagreements"] == 1
    assert s["counts"]["tomato"]["fresh"] == 1

    dataset.update_photo(cfg, "T0001", {"final_label": "sell_soon"})
    s = dataset.summary(cfg)
    assert s["disagreements"] == 0 and s["counts"]["tomato"]["sell_soon"] == 1

    with pytest.raises(dataset.UploadError):
        dataset.update_photo(cfg, "T0001", {"crop": "banana"})

    path = cfg.path_of("raw_dir") / "2026-11-03_kamembe/T0002.jpg"
    dataset.delete_photo(cfg, "T0002")
    assert not path.exists()
    assert dataset.read_metadata(cfg).image_id.tolist() == ["T0001"]


def test_http_upload_list_and_thumbnail(cfg):
    client = create_app(cfg).test_client()
    r = client.post("/api/photos", data={
        "crop": "banana", "label": "discount_today", "market": " Kamembe ", "district": "rusizi",
        "date": "2026-11-03", "phone_model": "Tecno", "batch_id": "kamembe_b1",
        "photos": [(io.BytesIO(jpg()), "x.jpg")],
    }, content_type="multipart/form-data")
    assert r.status_code == 200, r.json
    assert r.json["saved"] == 1

    d = client.get("/api/dataset").json
    assert d["summary"]["counts"]["banana"]["discount_today"] == 1
    photo = d["photos"][0]
    assert photo["market"] == "kamembe"

    t = client.get(f"/thumb/{photo['file']}")
    assert t.status_code == 200 and t.mimetype == "image/jpeg"
    assert client.get("/thumb/../config.yaml").status_code == 404

    bad = client.post("/api/photos", data={"crop": "banana"}, content_type="multipart/form-data")
    assert bad.status_code == 400


def test_train_rejects_unknown_model(cfg):
    client = create_app(cfg).test_client()
    assert client.post("/api/train", json={"model": "nope"}).status_code == 400
    assert client.get("/api/train/does-not-exist/log").status_code == 404

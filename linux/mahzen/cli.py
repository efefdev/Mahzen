"""Komut satırı: arayüzü olmayan sunucularda kasayı okumak, dosya eklemek ve yedeklemek için.

Örnekler::

    mahzen-cli bilgi "/media/ssd/Mahzen Kasası"
    mahzen-cli listele "/media/ssd/Mahzen Kasası"
    mahzen-cli disari "/media/ssd/Mahzen Kasası" fatura.pdf ~/Masaüstü
    mahzen-cli ekle "/media/ssd/Mahzen Kasası" belge.pdf Fotoğraflar/
    mahzen-cli dogrula "/media/ssd/Mahzen Kasası"
    mahzen-cli yedekle "/media/ssd/Mahzen Kasası" "/media/yedek/Mahzen Kasası Yedek"
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys

from .core import vault as vaultmod
from .core.errors import VaultError, WrongPassword
from .core.filetypes import content_type_for
from .core.importplan import ImportPlan
from .core.index import new_file_record, new_id, now
from .core.keyfiles import KeyfileStore
from .core.vault import Vault


def _read_password(args) -> str:
    if args.parola_stdin:
        return sys.stdin.readline().rstrip("\n")
    return getpass.getpass("Kasa parolası: ")


def _unlock(args) -> Vault:
    folder = args.kasa
    header = vaultmod.read_header(folder)
    password = _read_password(args)
    keyfiles: list[bytes] = []
    if args.anahtar:
        with open(args.anahtar, "rb") as f:
            keyfiles.append(f.read())
    keyfiles += KeyfileStore.standard().candidates(header.vault_id)
    for keyfile in keyfiles:
        try:
            return Vault.unlock(folder, password, keyfile)
        except WrongPassword:
            continue
    return Vault.unlock(folder, password)


def _size(n: int) -> str:
    for unit in ("bayt", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "bayt" else f"{n:.1f} {unit}"
        n /= 1000
    return str(n)


def cmd_info(args) -> int:
    header = vaultmod.read_header(args.kasa)
    print(f"Kasa kimliği : {header.vault_id}")
    print(f"Biçim        : {header.version}")
    print(f"Oluşturulma  : {header.raw.get('createdAt')}")
    print(f"Şifreleme    : AES-256-GCM · {header.kdf_summary}")
    return 0


def cmd_list(args) -> int:
    v = _unlock(args)
    idx, _ = v.load_index()
    files = idx.files if args.hepsi else idx.live_files
    for f in sorted(files, key=lambda f: ["/".join(p["name"] for p in idx.path_to(f.get("folderID"))), f["name"]]):
        path = "/".join([p["name"] for p in idx.path_to(f.get("folderID"))] + [f["name"]])
        mark = " (çöpte)" if f.get("deletedAt") else ""
        print(f"{f['id'][:8]}  {_size(int(f.get('size', 0))):>10}  {path}{mark}")
    notes = sum(1 for n in idx.notes if not n.get("deletedAt"))
    secrets = sum(1 for s in idx.secrets if not s.get("deletedAt"))
    print(f"\n{len(idx.live_files)} dosya · {notes} not · {secrets} parola kaydı", file=sys.stderr)
    return 0


def cmd_export(args) -> int:
    v = _unlock(args)
    idx, _ = v.load_index()
    query = args.dosya
    matches = [f for f in idx.live_files if f["id"].lower().startswith(query.lower()) or f["name"] == query]
    if not matches:
        print(f"Bulunamadı: {query}", file=sys.stderr)
        return 1
    os.makedirs(args.hedef, exist_ok=True)
    for f in matches:
        dest = os.path.join(args.hedef, os.path.basename(f["name"]))
        if os.path.exists(dest):
            print(f"Zaten var, atlandı: {dest}", file=sys.stderr)
            continue
        v.export_file(f["id"], dest)
        print(dest)
    return 0


def cmd_add(args) -> int:
    v = _unlock(args)
    idx, _ = v.load_index()
    plan = ImportPlan.build(args.kaynak)
    hashes = {f.get("sha256") for f in idx.live_files}
    added = 0
    for item in plan.items:
        fid = new_id()
        digest = v.import_file(item.path, fid)
        name = os.path.basename(item.path)
        if digest in hashes:
            v.delete_file(fid)
            print(f"Zaten kasada: {name}", file=sys.stderr)
            continue
        hashes.add(digest)
        folder = idx.ensure_folder_path(item.folder_path, None)
        idx.files.append(new_file_record(fid, name, item.size, content_type_for(name), item.modified, False,
                                         folder, digest))
        added += 1
        print(f"Eklendi: {name}")
    v.save_index(idx)
    if plan.skipped_count:
        print(f"{plan.skipped_count} öğe atlandı (gizli dosya, kısayol veya okunamayan öğe).", file=sys.stderr)
    print(f"{added} dosya şifrelendi.", file=sys.stderr)
    return 0


def cmd_verify(args) -> int:
    v = _unlock(args)
    idx, _ = v.load_index()
    report = v.check_integrity(idx.files)
    names = {f["id"]: f["name"] for f in idx.files}
    print(f"{report.checked_files} dosya ({_size(report.checked_bytes)}) doğrulandı.")
    for fid, problem in report.problems.items():
        print(f"SORUN  {names.get(fid, fid)}: {problem}")
    if report.orphan_paths:
        print(f"{len(report.orphan_paths)} sahipsiz dosya ({_size(report.orphan_bytes)}).")
    if not report.index_backup_readable:
        print("Dizin yedeği okunamıyor.")
    return 1 if report.problems else 0


def cmd_backup(args) -> int:
    v = _unlock(args)
    idx, _ = v.load_index()
    os.makedirs(args.hedef, exist_ok=True)
    report = v.backup(args.hedef, {f["id"] for f in idx.files}, {f["id"] for f in idx.files if f.get("hasThumbnail")})
    idx.preferences["lastBackupAt"] = now()
    v.save_index(idx)
    print(f"{report.copied_files} dosya kopyalandı ({_size(report.copied_bytes)}), "
          f"{report.unchanged_files} değişmemiş, {report.removed_files} eski kopya silindi.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mahzen-cli", description="Mahzen şifreli kasası için komut satırı.")
    sub = parser.add_subparsers(dest="komut", required=True)

    def add(name, help_text, fn, needs_password=True):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("kasa", help="kasa klasörü")
        if needs_password:
            p.add_argument("--parola-stdin", action="store_true", help="parolayı standart girdiden oku")
            p.add_argument("--anahtar", help="anahtar dosyası (.mahzenkey)")
        p.set_defaults(fn=fn)
        return p

    add("bilgi", "kasa başlığını göster (parola gerekmez)", cmd_info, needs_password=False)
    add("listele", "dosyaları listele", cmd_list).add_argument("--hepsi", action="store_true",
                                                               help="çöp kutusundakileri de göster")
    p = add("disari", "dosyayı şifresini çözerek dışa aktar", cmd_export)
    p.add_argument("dosya", help="dosya adı ya da kimliğin başı")
    p.add_argument("hedef", help="hedef klasör")
    add("ekle", "dosya veya klasörleri şifreleyip ekle", cmd_add).add_argument("kaynak", nargs="+")
    add("dogrula", "bütünlük taraması", cmd_verify)
    add("yedekle", "artımlı yedek al", cmd_backup).add_argument("hedef", help="yedek klasörü")

    args = parser.parse_args(argv)
    try:
        return args.fn(args)
    except VaultError as e:
        print(e, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130
    except OSError as e:
        print(f"{e.strerror or e}: {e.filename or ''}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

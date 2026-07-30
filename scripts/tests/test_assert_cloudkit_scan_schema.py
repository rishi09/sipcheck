import unittest

from scripts.assert_cloudkit_scan_schema import assert_schema, patch_scan_record


def schema(scan_body: str, extra: str = "") -> str:
    return f"""DEFINE SCHEMA
RECORD TYPE Other (
    factSourceKind STRING,
    factSourceURL STRING,
    GRANT READ TO \"_creator\"
);
{extra}
RECORD TYPE Scan (
{scan_body}
    GRANT WRITE TO \"_creator\",
    GRANT READ TO \"_creator\"
);
"""


class CloudKitScanSchemaTests(unittest.TestCase):
    def test_patches_both_missing_fields_and_is_idempotent(self):
        original = schema("    beerName STRING,\n")

        patched, inserted = patch_scan_record(original)
        assert_schema(patched)
        again, inserted_again = patch_scan_record(patched)

        self.assertEqual(inserted, ["factSourceKind", "factSourceURL"])
        self.assertEqual(inserted_again, [])
        self.assertEqual(again, patched)
        self.assertEqual(patched.count("factSourceKind STRING"), 2)  # Other + Scan
        self.assertEqual(patched.count("factSourceURL STRING"), 2)

    def test_patches_only_the_missing_field(self):
        original = schema("    factSourceKind STRING,\n")

        patched, inserted = patch_scan_record(original)

        self.assertEqual(inserted, ["factSourceURL"])
        assert_schema(patched)

    def test_accepts_both_fields_and_quoted_identifiers(self):
        original = schema(
            '    FIELD "factSourceKind" STRING,\n'
            '    "factSourceURL" STRING,\n'
        )

        patched, inserted = patch_scan_record(original)

        self.assertEqual(inserted, [])
        self.assertEqual(patched, original)
        assert_schema(patched)

    def test_rejects_wrong_type_instead_of_adding_a_duplicate(self):
        with self.assertRaisesRegex(ValueError, "incompatible type"):
            patch_scan_record(schema("    factSourceKind INT64,\n"))

    def test_rejects_wrong_case(self):
        with self.assertRaisesRegex(ValueError, "incompatible letter case"):
            patch_scan_record(schema("    factsourcekind STRING,\n"))

    def test_rejects_duplicate_declaration(self):
        with self.assertRaisesRegex(ValueError, "declared more than once"):
            patch_scan_record(
                schema(
                    "    factSourceKind STRING,\n"
                    "    factSourceKind STRING,\n"
                )
            )

    def test_does_not_accept_fields_from_another_record(self):
        patched, inserted = patch_scan_record(schema("    beerName STRING,\n"))

        self.assertEqual(inserted, ["factSourceKind", "factSourceURL"])
        assert_schema(patched)

    def test_rejects_missing_grant_boundary(self):
        original = """DEFINE SCHEMA
RECORD TYPE Scan (
    beerName STRING
);
"""
        with self.assertRaisesRegex(ValueError, "no GRANT boundary"):
            patch_scan_record(original)

    def test_rejects_malformed_and_missing_scan_blocks(self):
        with self.assertRaisesRegex(ValueError, "not balanced"):
            patch_scan_record("RECORD TYPE Scan (\n beerName STRING,\n")
        with self.assertRaisesRegex(ValueError, "no Scan record type"):
            patch_scan_record("RECORD TYPE Other ( value STRING );")

    def test_scan_record_name_is_case_sensitive(self):
        with self.assertRaisesRegex(ValueError, "no Scan record type"):
            patch_scan_record("RECORD TYPE scan ( value STRING );")


if __name__ == "__main__":
    unittest.main()

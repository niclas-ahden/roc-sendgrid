# Migration to the zig-based Roc compiler

package/ is ported: hooks record replaces module params, optional fields
are Try(a, [Missing]), and the payload is built as JSON text by hand
because the SendGrid schema needs a "type" key, which is not a legal Roc
field name (EmailContent.mime_type emits it). dynamic_template_data is
now pre-encoded JSON text supplied by the caller. The apps in tests/
still target the old compiler and platform releases.

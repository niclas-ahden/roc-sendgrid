# roc-sendgrid

Send emails via the [SendGrid v3 API](https://docs.sendgrid.com/api-reference/mail-send/mail-send) from Roc.

## Example usage

```roc
app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    sendgrid: "https://github.com/niclas-ahden/roc-sendgrid/releases/download/0.1.0/HASH.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import pf.Http
import json.Option

import sendgrid.SendGrid {
    http_send!: Http.send!,
    http_header: Http.header,
}

main! = |_args|
    session = { api_key: "SG.your-api-key" }

    SendGrid.send_email!(
        {
            from: { email: "noreply@example.com", name: Option.none({}) },
            recipients: {
                to: [{ email: "user@example.com", name: Option.some("User") }],
                cc: Option.none({}),
                bcc: Option.none({}),
            },
            subject: "Hello from Roc!",
            content: [{ type: "text/plain", value: "Sent via roc-sendgrid." }],
            reply_to: Option.none({}),
            template_id: Option.none({}),
        },
        session,
    )
    |> Result.map_ok(|_| {})
    |> Result.map_err(
        |SendGridError(msg)| Exit(1, msg),
    )
```

## Requirements

- A platform that exposes HTTP sending (like [`growthagent/basic-cli`](https://github.com/growthagent/basic-cli))
- A SendGrid API key

## API

### `send_email!`

Send a plain text or HTML email. Supports to/cc/bcc recipients and optional reply-to.

### `send_template_email!`

Send an email using a SendGrid dynamic template. Pass template variables via `dynamic_template_data`.

## Testing

Payload structure is validated against the [SendGrid OpenAPI spec](https://github.com/twilio/sendgrid-oai) using [roc-openapi](https://github.com/niclas-ahden/roc-openapi). Every payload variant (full, minimal, template, multi-recipient) is checked against the real API contract.

## Status

`roc-sendgrid` uses the old Rust-based Roc compiler, and will move to the new Zig-based one when possible.

## Documentation

View the full API documentation at [https://niclas-ahden.github.io/roc-sendgrid/](https://niclas-ahden.github.io/roc-sendgrid/).

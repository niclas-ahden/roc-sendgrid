app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    sendgrid: "../package/main.roc",
    openapi: "/home/niclas/dev/roc-openapi/package/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import pf.Arg
import pf.File
import pf.Http
import pf.Stdout

import json.Option

import openapi.OpenApi

import sendgrid.SendGrid {
    http_send!: capture_and_validate!,
    http_header: Http.header,
}

## Validates that every payload variant produced by roc-sendgrid conforms
## to the SendGrid OpenAPI spec, using roc-openapi for validation.

spec_path = "spec/tsg_mail_v3.json"

main! : List Arg.Arg => Result {} _
main! = |_args|
    # Full email with all optional fields set
    _ = SendGrid.send_email!(
        {
            from: { email: "sender@example.com", name: Option.some("Sender") },
            recipients: {
                to: [{ email: "to@example.com", name: Option.some("Recipient") }],
                cc: Option.some([{ email: "cc@example.com", name: Option.none({}) }]),
                bcc: Option.some([{ email: "bcc@example.com", name: Option.none({}) }]),
            },
            subject: "Full email test",
            content: [
                { type: "text/plain", value: "Plain text" },
                { type: "text/html", value: "<p>HTML</p>" },
            ],
            reply_to: Option.some({ email: "reply@example.com", name: Option.none({}) }),
            template_id: Option.none({}),
        },
        { api_key: "SG.test" },
    )?

    # Minimal email — all optional fields None
    _ = SendGrid.send_email!(
        {
            from: { email: "sender@example.com", name: Option.none({}) },
            recipients: {
                to: [{ email: "to@example.com", name: Option.none({}) }],
                cc: Option.none({}),
                bcc: Option.none({}),
            },
            subject: "Minimal",
            content: [{ type: "text/plain", value: "Hello" }],
            reply_to: Option.none({}),
            template_id: Option.none({}),
        },
        { api_key: "SG.test" },
    )?

    # Template email with dynamic data
    _ = SendGrid.send_template_email!(
        {
            from: { email: "sender@example.com", name: Option.none({}) },
            recipients: {
                to: [{ email: "to@example.com", name: Option.none({}) }],
                cc: Option.none({}),
                bcc: Option.none({}),
            },
            subject: "Template",
            template_id: "d-abc123",
            dynamic_template_data: Option.some({ name: "Anna" }),
            reply_to: Option.none({}),
        },
        { api_key: "SG.test" },
    )?

    # Multiple recipients
    _ = SendGrid.send_email!(
        {
            from: { email: "sender@example.com", name: Option.none({}) },
            recipients: {
                to: [
                    { email: "alice@example.com", name: Option.some("Alice") },
                    { email: "bob@example.com", name: Option.some("Bob") },
                ],
                cc: Option.some([{ email: "cc@example.com", name: Option.none({}) }]),
                bcc: Option.some([{ email: "bcc@example.com", name: Option.none({}) }]),
            },
            subject: "Multi",
            content: [{ type: "text/plain", value: "Hello all" }],
            reply_to: Option.none({}),
            template_id: Option.none({}),
        },
        { api_key: "SG.test" },
    )?

    Stdout.line!("All payloads validated against SendGrid OpenAPI spec")

## Fake http_send! that validates the request body against the OpenAPI spec.
## Checks for Option.none leaks, then validates against the SendGrid spec.
capture_and_validate! : _ => Result _ _
capture_and_validate! = |request|
    body_str = Str.from_utf8(request.body) |> Result.with_default("")

    # Check for roc-json Option.none leak
    if Str.contains(body_str, "\"None\"") then
        Err(OptionNoneLeaked(body_str))
    else
        spec = File.read_bytes!(spec_path)
            |> Result.map_err(|e| SpecReadFailed(Inspect.to_str(e)))?

        errors = OpenApi.validate_request({
            spec,
            method: "post",
            path: "/v3/mail/send",
            body: request.body,
        })
            |> Result.map_err(|e| ValidationSetupFailed(Inspect.to_str(e)))?

        when errors is
            [] -> Ok({ status: 202, headers: [], body: [] })
            _ ->
                error_msgs = List.map(errors, |e|
                    path_str = Str.join_with(e.path, ".")
                    "${path_str}: ${e.message} (${e.keyword})"
                )
                Err(SchemaValidationFailed(error_msgs))

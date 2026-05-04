app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    sendgrid: "../package/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import pf.Arg
import pf.Http

import json.Option

import sendgrid.SendGrid {
    http_send!: fake_http_send!,
    http_header: Http.header,
}

## Tests that send_email! sends to the right URL with correct headers.
## The OpenAPI test covers payload structure; this covers everything else.

main! : List Arg.Arg => Result {} _
main! = |_args|
    result = SendGrid.send_email!(
        {
            from: { email: "s@test.com", name: Option.none({}) },
            recipients: {
                to: [{ email: "t@test.com", name: Option.none({}) }],
                cc: Option.none({}),
                bcc: Option.none({}),
            },
            subject: "Test",
            content: [{ type: "text/plain", value: "x" }],
            reply_to: Option.none({}),
            template_id: Option.none({}),
        },
        { api_key: "SG.my-secret-key" },
    )

    when result is
        Ok({ status }) if status == 202 -> Ok({})
        Ok({ status }) -> Err(UnexpectedStatus(status))
        Err(SendGridError(msg)) -> Err(UnexpectedError(msg))

fake_http_send! : _ => Result _ _
fake_http_send! = |request|
    if request.uri != "https://api.sendgrid.com/v3/mail/send" then
        Err(WrongUrl(request.uri))
    else if !(request.method == POST) then
        Err(WrongMethod)
    else if !(List.any(request.headers, |h| h.name == "Authorization" && h.value == "Bearer SG.my-secret-key")) then
        Err(WrongAuth)
    else if !(List.any(request.headers, |h| h.name == "Content-Type" && h.value == "application/json")) then
        Err(MissingContentType)
    else
        Ok({ status: 202, headers: [], body: [] })

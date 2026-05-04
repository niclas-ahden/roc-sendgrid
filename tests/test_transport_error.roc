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

## Tests that an HTTP transport failure becomes SendGridError.

main! : List Arg.Arg => Result {} _
main! = |_args|
    result = SendGrid.send_email!(
        {
            from: { email: "s@t.com", name: Option.none({}) },
            recipients: { to: [{ email: "r@t.com", name: Option.none({}) }], cc: Option.none({}), bcc: Option.none({}) },
            subject: "X",
            content: [{ type: "text/plain", value: "x" }],
            reply_to: Option.none({}),
            template_id: Option.none({}),
        },
        { api_key: "SG.test" },
    )

    when result is
        Ok(_) -> Err(ShouldHaveFailed)
        Err(SendGridError(msg)) ->
            if Str.contains(msg, "HTTP request failed") then
                Ok({})
            else
                Err(WrongErrorMessage(msg))

fake_http_send! : _ => Result _ _
fake_http_send! = |_request|
    Err(ConnectionTimeout)

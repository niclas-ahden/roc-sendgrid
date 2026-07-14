## SendGrid v3 mail send API client.
##
## The package cannot import platform modules, so the platform's HTTP send
## arrives through a hooks record passed to every effectful function:
##
## ```
## hooks = { http_send!: Http.send! }
## SendGrid.send_email!(hooks, email_request, { api_key: key })?
## ```
##
## The request payload is built as JSON text by hand because the SendGrid
## schema needs a "type" key, which is not a legal Roc field name. Optional
## fields are `Try(a, [Missing])` and `Err(Missing)` fields are omitted from
## the payload, matching how the builtin Json module treats them.
SendGrid := [].{
    ## Email address with optional display name.
    EmailAddress : { email : Str, name : Try(Str, [Missing]) }

    ## Email content. `mime_type` is emitted as the JSON "type" key.
    EmailContent : { mime_type : Str, value : Str }

    ## Recipients for an email. to is required, cc and bcc are optional.
    Recipients : {
        to : List(SendGrid.EmailAddress),
        cc : Try(List(SendGrid.EmailAddress), [Missing]),
        bcc : Try(List(SendGrid.EmailAddress), [Missing]),
    }

    ## Complete email request.
    EmailRequest : {
        from : SendGrid.EmailAddress,
        recipients : SendGrid.Recipients,
        subject : Str,
        content : List(SendGrid.EmailContent),
        reply_to : Try(SendGrid.EmailAddress, [Missing]),
        template_id : Try(Str, [Missing]),
    }

    ## SendGrid session holding the API key.
    Session : { api_key : Str }

    ## Response from the SendGrid API.
    Response : { status : U16 }

    ## Send an email via SendGrid.
    send_email! : _, SendGrid.EmailRequest, SendGrid.Session => Try(SendGrid.Response, [SendGridError(Str)])
    send_email! = |hooks, email_request, session|
        send_request!(hooks, SendGrid.email_request_json(email_request), session)

    ## Send an email using a SendGrid dynamic template.
    ##
    ## `dynamic_template_data` is PRE-ENCODED JSON text (encode your record
    ## with `Json.to_str` at the call site, where its type is concrete), or
    ## `Err(Missing)` to skip it.
    send_template_email! :
        _,
        {
            from : SendGrid.EmailAddress,
            recipients : SendGrid.Recipients,
            subject : Str,
            template_id : Str,
            dynamic_template_data : Try(Str, [Missing]),
            reply_to : Try(SendGrid.EmailAddress, [Missing]),
        },
        SendGrid.Session
        => Try(SendGrid.Response, [SendGridError(Str)])
    send_template_email! = |hooks, req, session|
        send_request!(hooks, SendGrid.template_request_json(req), session)

    ## The JSON payload for [SendGrid.send_email!]. Public so it can be
    ## tested without performing IO.
    email_request_json : SendGrid.EmailRequest -> Str
    email_request_json = |req| {
        personalization = object(
            [
                Ok(("to", address_list_json(req.recipients.to))),
                req.recipients.cc.map_ok(|cc| ("cc", address_list_json(cc))),
                req.recipients.bcc.map_ok(|bcc| ("bcc", address_list_json(bcc))),
                Ok(("subject", json_str(req.subject))),
            ],
        )

        content_items = Str.join_with(req.content.map(content_json), ",")

        object(
            [
                Ok(("personalizations", "[${personalization}]")),
                Ok(("from", address_json(req.from))),
                Ok(("content", "[${content_items}]")),
                req.reply_to.map_ok(|a| ("reply_to", address_json(a))),
                req.template_id.map_ok(|t| ("template_id", json_str(t))),
            ],
        )
    }

    ## The JSON payload for [SendGrid.send_template_email!]. Public so it can
    ## be tested without performing IO.
    template_request_json :
        {
            from : SendGrid.EmailAddress,
            recipients : SendGrid.Recipients,
            subject : Str,
            template_id : Str,
            dynamic_template_data : Try(Str, [Missing]),
            reply_to : Try(SendGrid.EmailAddress, [Missing]),
        }
        -> Str
    template_request_json = |req| {
        personalization = object(
            [
                Ok(("to", address_list_json(req.recipients.to))),
                req.recipients.cc.map_ok(|cc| ("cc", address_list_json(cc))),
                req.recipients.bcc.map_ok(|bcc| ("bcc", address_list_json(bcc))),
                Ok(("subject", json_str(req.subject))),
                req.dynamic_template_data.map_ok(|d| ("dynamic_template_data", d)),
            ],
        )

        object(
            [
                Ok(("personalizations", "[${personalization}]")),
                Ok(("from", address_json(req.from))),
                Ok(("template_id", json_str(req.template_id))),
                req.reply_to.map_ok(|a| ("reply_to", address_json(a))),
            ],
        )
    }
}

sendgrid_api_url : Str
sendgrid_api_url = "https://api.sendgrid.com/v3/mail/send"

## JSON-encode a string (quotes and escapes included).
json_str : Str -> Str
json_str = |s| Json.to_str(s)

## Build a JSON object from optional ("key", encoded_value) pairs, skipping
## the Err(Missing) ones.
object : List(Try((Str, Str), [Missing])) -> Str
object = |fields| {
    parts = fields.fold(
        [],
        |acc, field|
            match field {
                Ok((key, value)) => acc.append("${json_str(key)}:${value}")
                Err(Missing) => acc
            },
    )
    "{${Str.join_with(parts, ",")}}"
}

address_json : { email : Str, name : Try(Str, [Missing]) } -> Str
address_json = |a|
    object(
        [
            Ok(("email", json_str(a.email))),
            a.name.map_ok(|n| ("name", json_str(n))),
        ],
    )

address_list_json : List({ email : Str, name : Try(Str, [Missing]) }) -> Str
address_list_json = |addrs|
    "[${Str.join_with(addrs.map(address_json), ",")}]"

content_json : { mime_type : Str, value : Str } -> Str
content_json = |c|
    object(
        [
            Ok(("type", json_str(c.mime_type))),
            Ok(("value", json_str(c.value))),
        ],
    )

## Send pre-built JSON to the SendGrid API.
send_request! = |hooks, body_json, session| {
    request = {
        uri: sendgrid_api_url,
        method: POST,
        headers: [
            { name: "Authorization", value: "Bearer ${session.api_key}" },
            { name: "Content-Type", value: "application/json" },
        ],
        body: Str.to_utf8(body_json),
        timeout_ms: TimeoutMilliseconds(30_000),
    }

    match hooks.http_send!(request) {
        Ok(response) =>
            if response.status >= 200 and response.status < 300 {
                Ok({ status: response.status })
            } else {
                Err(SendGridError("SendGrid API error: status ${response.status.to_str()}"))
            }
        Err(http_error) =>
            Err(SendGridError("HTTP request failed: ${Str.inspect(http_error)}"))
    }
}

expect {
    minimal : SendGrid.EmailRequest
    minimal = {
        from: { email: "from@example.com", name: Err(Missing) },
        recipients: { to: [{ email: "to@example.com", name: Ok("To Person") }], cc: Err(Missing), bcc: Err(Missing) },
        subject: "Hello",
        content: [{ mime_type: "text/plain", value: "Hi there" }],
        reply_to: Err(Missing),
        template_id: Err(Missing),
    }
    output = SendGrid.email_request_json(minimal)
    expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\",\"name\":\"To Person\"}],\"subject\":\"Hello\"}],\"from\":{\"email\":\"from@example.com\"},\"content\":[{\"type\":\"text/plain\",\"value\":\"Hi there\"}]}"
    output == expected
}

expect {
    full : SendGrid.EmailRequest
    full = {
        from: { email: "from@example.com", name: Ok("Sender") },
        recipients: {
            to: [{ email: "a@example.com", name: Err(Missing) }, { email: "b@example.com", name: Ok("B") }],
            cc: Ok([{ email: "cc@example.com", name: Err(Missing) }]),
            bcc: Ok([{ email: "bcc@example.com", name: Err(Missing) }]),
        },
        subject: "Quoted \"subject\"",
        content: [{ mime_type: "text/html", value: "<b>Hi</b>" }],
        reply_to: Ok({ email: "reply@example.com", name: Err(Missing) }),
        template_id: Ok("d-123"),
    }
    output = SendGrid.email_request_json(full)
    expected = "{\"personalizations\":[{\"to\":[{\"email\":\"a@example.com\"},{\"email\":\"b@example.com\",\"name\":\"B\"}],\"cc\":[{\"email\":\"cc@example.com\"}],\"bcc\":[{\"email\":\"bcc@example.com\"}],\"subject\":\"Quoted \\\"subject\\\"\"}],\"from\":{\"email\":\"from@example.com\",\"name\":\"Sender\"},\"content\":[{\"type\":\"text/html\",\"value\":\"<b>Hi</b>\"}],\"reply_to\":{\"email\":\"reply@example.com\"},\"template_id\":\"d-123\"}"
    output == expected
}

expect {
    templated = SendGrid.template_request_json(
        {
            from: { email: "from@example.com", name: Err(Missing) },
            recipients: { to: [{ email: "to@example.com", name: Err(Missing) }], cc: Err(Missing), bcc: Err(Missing) },
            subject: "Tpl",
            template_id: "d-456",
            dynamic_template_data: Ok("{\"video_count\":3}"),
            reply_to: Err(Missing),
        },
    )
    expected = "{\"personalizations\":[{\"to\":[{\"email\":\"to@example.com\"}],\"subject\":\"Tpl\",\"dynamic_template_data\":{\"video_count\":3}}],\"from\":{\"email\":\"from@example.com\"},\"template_id\":\"d-456\"}"
    templated == expected
}

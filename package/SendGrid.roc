module
    {
        http_send!,
        http_header,
    } -> [
        EmailAddress,
        EmailContent,
        EmailRequest,
        Recipients,
        Session,
        Response,
        send_email!,
        send_template_email!,
    ]

import json.Json
import json.Option exposing [Option]

## Email address with optional display name.
EmailAddress : {
    email : Str,
    name : Option Str,
}

## Email content with MIME type and value.
EmailContent : {
    type : Str,
    value : Str,
}

## Recipients for an email — to is required, cc and bcc are optional.
Recipients : {
    to : List EmailAddress,
    cc : Option (List EmailAddress),
    bcc : Option (List EmailAddress),
}

## Complete email request.
EmailRequest : {
    from : EmailAddress,
    recipients : Recipients,
    subject : Str,
    content : List EmailContent,
    reply_to : Option EmailAddress,
    template_id : Option Str,
}

## SendGrid session holding the API key.
Session : {
    api_key : Str,
}

## Response from the SendGrid API.
Response : {
    status : U16,
}

sendgrid_api_url : Str
sendgrid_api_url = "https://api.sendgrid.com/v3/mail/send"

## Explicit payload types to avoid compiler panics with Encode.to_bytes

EmailPayload : {
    personalizations : List EmailPersonalization,
    from : EmailAddress,
    content : List EmailContent,
    reply_to : Option EmailAddress,
    template_id : Option Str,
}

EmailPersonalization : {
    to : List EmailAddress,
    cc : Option (List EmailAddress),
    bcc : Option (List EmailAddress),
    subject : Str,
}

## Send an email via SendGrid.
send_email! : EmailRequest, Session => Result Response [SendGridError Str]
send_email! = |email_request, session|
    payload : EmailPayload
    payload = {
        personalizations: [{
            to: email_request.recipients.to,
            cc: email_request.recipients.cc,
            bcc: email_request.recipients.bcc,
            subject: email_request.subject,
        }],
        from: email_request.from,
        content: email_request.content,
        reply_to: email_request.reply_to,
        template_id: email_request.template_id,
    }

    body = Encode.to_bytes(payload, Json.utf8)
    send_request!(body, session)

## Send an email using a SendGrid dynamic template.
##
## `dynamic_template_data` is any record that will be JSON-encoded and passed
## to the template as merge variables. Use `Option.none({})` to skip it.
send_template_email! :
    {
        from : EmailAddress,
        recipients : Recipients,
        subject : Str,
        template_id : Str,
        dynamic_template_data : Option _,
        reply_to : Option EmailAddress,
    },
    Session
    => Result Response [SendGridError Str]
send_template_email! = |{ from, recipients, subject, template_id, dynamic_template_data, reply_to }, session|
    # No named type annotation here because dynamic_template_data is generic (Option _).
    # The Encode.to_bytes call infers the type from the record structure.
    payload = {
        personalizations: [{
            to: recipients.to,
            cc: recipients.cc,
            bcc: recipients.bcc,
            subject,
            dynamic_template_data,
        }],
        from,
        template_id: Option.some(template_id),
        reply_to,
    }

    body = Encode.to_bytes(payload, Json.utf8)
    send_request!(body, session)

# Internal: send pre-encoded bytes
send_request! : List U8, Session => Result Response [SendGridError Str]
send_request! = |body, session|
    request = {
        uri: sendgrid_api_url,
        method: POST,
        headers: [
            http_header(("Authorization", "Bearer ${session.api_key}")),
            http_header(("Content-Type", "application/json")),
        ],
        body,
        timeout_ms: TimeoutMilliseconds(30_000),
    }

    when http_send!(request) is
        Ok(response) ->
            if response.status >= 200 && response.status < 300 then
                Ok({ status: response.status })
            else
                    Err(SendGridError("SendGrid API error: status ${Num.to_str(response.status)}"))

        Err(http_error) ->
            Err(SendGridError("HTTP request failed: ${Inspect.to_str(http_error)}"))

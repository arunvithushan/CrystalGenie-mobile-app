"""Outgoing e-mail. Uses SMTP when configured, otherwise writes messages to var/outbox/ (dev)."""
from __future__ import annotations

import logging
import smtplib
import ssl
from datetime import datetime, timezone
from email.message import EmailMessage

from app.core.config import get_settings

log = logging.getLogger("app.email")


def send_email(to: str, subject: str, body: str) -> None:
    s = get_settings()
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = s.smtp_from, to, subject
    msg.set_content(body)
    if s.smtp_host:
        try:
            with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=15) as smtp:
                if s.smtp_starttls:
                    smtp.starttls(context=ssl.create_default_context())
                if s.smtp_user:
                    smtp.login(s.smtp_user, s.smtp_password)
                smtp.send_message(msg)
            log.info("email sent", extra={"event": "email_sent"})
        except Exception:  # noqa: BLE001 - never leak SMTP errors to clients
            log.exception("email delivery failed")
        return
    s.outbox_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    (s.outbox_dir / f"{stamp}.eml").write_bytes(bytes(msg))
    log.info("email written to outbox (SMTP not configured)", extra={"event": "email_outbox"})


def send_password_reset(to: str, name: str, code: str, minutes: int) -> None:
    body = (
        f"Hi {name},\n\n"
        f"Use this code to reset your Crystal Genie password: {code}\n\n"
        f"The code expires in {minutes} minutes. If you did not request a reset, you can ignore this e-mail.\n\n"
        "— Crystal Genie"
    )
    send_email(to, "Your Crystal Genie password reset code", body)

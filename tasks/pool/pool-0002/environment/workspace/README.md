# codec

Encoder and decoder for the Lanner wire protocol. `encode(message)` and `decode(frame)` are inverses. A message is a dict with a `type` key plus one key per field of that message type. Errors live in `codec/errors.py`.

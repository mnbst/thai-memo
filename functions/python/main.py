try:
    from .notification_handlers import sendDailySentence
    from .sentence_handlers import generateThaiSentence
    from .uvm_handlers import updateUvm
except ImportError:
    from notification_handlers import sendDailySentence
    from sentence_handlers import generateThaiSentence
    from uvm_handlers import updateUvm

__all__ = [
    "generateThaiSentence",
    "sendDailySentence",
    "updateUvm",
]

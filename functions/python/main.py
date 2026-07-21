try:
    from .daily_sentence_handlers import deliverDailySentence
    from .sentence_handlers import generateThaiSentence
    from .uvm_handlers import updateUvm
except ImportError:
    from daily_sentence_handlers import deliverDailySentence
    from sentence_handlers import generateThaiSentence
    from uvm_handlers import updateUvm

__all__ = [
    "deliverDailySentence",
    "generateThaiSentence",
    "updateUvm",
]

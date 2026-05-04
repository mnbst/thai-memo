try:
    from .sentence_handlers import generateThaiSentence
    from .uvm_handlers import updateUvm
except ImportError:
    from sentence_handlers import generateThaiSentence
    from uvm_handlers import updateUvm

__all__ = [
    "generateThaiSentence",
    "updateUvm",
]

try:
    from .sentence_handlers import generateBatchSentences, generateThaiSentence
    from .uvm_handlers import updateUvm
except ImportError:
    from sentence_handlers import generateBatchSentences, generateThaiSentence
    from uvm_handlers import updateUvm

__all__ = [
    "generateBatchSentences",
    "generateThaiSentence",
    "updateUvm",
]

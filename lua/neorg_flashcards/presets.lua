local M = {}

M.japanese = {
  label = "Japanese word → reading + English",
  front = "japanese",
  fields = {
    {
      key = "japanese",
      label = "Japanese: ",
      title = "Japanese",
      required = true,
      placeholder = "e.g. 猫",
      help = "Word or expression as written in Japanese",
    },
    {
      key = "reading",
      label = "Reading: ",
      title = "Reading",
      reveal = true,
      typed_answer = true,
      placeholder = "e.g. ねこ",
      help = "Kana reading or pronunciation",
    },
    {
      key = "english",
      label = "English: ",
      title = "English",
      required = true,
      reveal = true,
      typed_answer = true,
      placeholder = "e.g. cat",
      help = "Meaning shown after the card is revealed",
    },
    {
      key = "notes",
      label = "Notes: ",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Grammar, usage, or a mnemonic",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      label = "Tags: ",
      title = "Tags",
      placeholder = "e.g. jlpt-n5 animals",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.chinese = {
  label = "Chinese",
  front = "chinese",
  fields = {
    {
      key = "chinese",
      label = "Chinese: ",
      title = "Chinese",
      required = true,
      placeholder = "e.g. 猫",
      help = "Word or expression as written in Chinese",
    },
    {
      key = "pinyin",
      label = "Pinyin: ",
      title = "Pinyin",
      reveal = true,
      typed_answer = true,
      placeholder = "e.g. māo",
      help = "Pronunciation with tone marks or numbers",
    },
    {
      key = "english",
      label = "English: ",
      title = "English",
      required = true,
      reveal = true,
      typed_answer = true,
      placeholder = "e.g. cat",
      help = "Meaning shown after the card is revealed",
    },
    {
      key = "notes",
      label = "Notes: ",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Usage, measure word, or a mnemonic",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      label = "Tags: ",
      title = "Tags",
      placeholder = "e.g. hsk-1 animals",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.question_answer = {
  label = "Question and answer",
  front = "question",
  fields = {
    {
      key = "question",
      title = "Question",
      required = true,
      multiline = true,
      placeholder = "What do you want to remember?",
      help = "The question shown before the answer is revealed",
    },
    {
      key = "answer",
      title = "Answer",
      required = true,
      reveal = true,
      multiline = true,
      placeholder = "Write the answer in your own words",
      help = "The answer shown after the card is revealed",
    },
    {
      key = "notes",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Context, a source, or a useful detail",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. algorithms graphs",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.term_definition = {
  label = "Term and definition",
  front = "term",
  fields = {
    {
      key = "term",
      title = "Term",
      required = true,
      placeholder = "e.g. idempotent",
      help = "The term or concept to recall",
    },
    {
      key = "definition",
      title = "Definition",
      required = true,
      reveal = true,
      multiline = true,
      placeholder = "Define it without using the term itself",
      help = "The definition shown after the card is revealed",
    },
    {
      key = "example",
      title = "Example",
      reveal = true,
      multiline = true,
      placeholder = "A short example or counterexample",
      help = "Optional example shown with the definition",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. distributed-systems concepts",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.code_output = {
  label = "Code output",
  front = "code",
  fields = {
    {
      key = "code",
      title = "Code",
      required = true,
      multiline = true,
      placeholder = "Paste a small snippet",
      help = "Code to read and reason about; it is never executed",
    },
    {
      key = "output",
      title = "Output",
      required = true,
      reveal = true,
      multiline = true,
      placeholder = "What does the snippet produce?",
      help = "Expected output or result shown after reveal",
    },
    {
      key = "explanation",
      title = "Explanation",
      reveal = true,
      multiline = true,
      placeholder = "Why does it behave that way?",
      help = "Optional reasoning shown with the output",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. lua tables",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.japanese_production = {
  label = "English → Japanese word",
  front = "english",
  fields = {
    {
      key = "english",
      title = "English",
      required = true,
      placeholder = "e.g. cat",
      help = "Meaning to produce in Japanese",
    },
    {
      key = "japanese",
      title = "Japanese",
      required = true,
      reveal = true,
      typed_answer = true,
      placeholder = "e.g. 猫",
      help = "Japanese answer shown after reveal",
    },
    {
      key = "reading",
      title = "Reading",
      reveal = true,
      placeholder = "e.g. ねこ",
      help = "Kana reading or pronunciation",
    },
    {
      key = "notes",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Grammar, usage, or a mnemonic",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. jlpt-n5 animals",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.japanese_kanji = {
  label = "Kanji → reading + meaning",
  front = "kanji",
  fields = {
    {
      key = "kanji",
      title = "Kanji",
      required = true,
      placeholder = "e.g. 学",
      help = "Kanji shown before the answer is revealed",
    },
    {
      key = "reading",
      title = "Reading",
      required = true,
      reveal = true,
      placeholder = "e.g. がく / まなぶ",
      help = "Useful on- or kun-reading",
    },
    {
      key = "meaning",
      title = "Meaning",
      required = true,
      reveal = true,
      placeholder = "e.g. study, learning",
      help = "Core meaning shown after reveal",
    },
    {
      key = "example",
      title = "Example",
      reveal = true,
      multiline = true,
      placeholder = "e.g. 学校（がっこう） school",
      help = "Optional word or sentence using the kanji",
    },
    {
      key = "notes",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Components, stroke cue, or mnemonic",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. jlpt-n5 kanji",
      help = "Space- or comma-separated study tags",
    },
  },
}

M.japanese_sentence = {
  label = "Japanese sentence → English",
  front = "japanese",
  fields = {
    {
      key = "japanese",
      title = "Japanese",
      required = true,
      multiline = true,
      placeholder = "e.g. 毎朝コーヒーを飲みます。",
      help = "Sentence shown before the answer is revealed",
    },
    {
      key = "reading",
      title = "Reading",
      reveal = true,
      multiline = true,
      placeholder = "e.g. まいあさコーヒーをのみます。",
      help = "Optional kana reading",
    },
    {
      key = "english",
      title = "English",
      required = true,
      reveal = true,
      multiline = true,
      placeholder = "e.g. I drink coffee every morning.",
      help = "Meaning shown after reveal",
    },
    {
      key = "notes",
      title = "Notes",
      reveal = true,
      multiline = true,
      placeholder = "Grammar, nuance, or source context",
      help = "Optional context shown with the answer",
    },
    {
      key = "tags",
      title = "Tags",
      placeholder = "e.g. jlpt-n5 routine",
      help = "Space- or comma-separated study tags",
    },
  },
}

function M.only(...)
  local schemas = {}
  for _, name in ipairs({ ... }) do
    if type(name) ~= "string" or type(M[name]) ~= "table" then
      error("unknown flashcard preset: " .. tostring(name), 2)
    end
    schemas[name] = vim.deepcopy(M[name])
  end
  return schemas
end

return M

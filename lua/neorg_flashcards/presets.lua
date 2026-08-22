local M = {}

M.japanese = {
  label = "Japanese",
  front = "japanese",
  aliases = {
    japanese = { "word" },
  },
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
      placeholder = "e.g. ねこ",
      help = "Kana reading or pronunciation",
    },
    {
      key = "english",
      label = "English: ",
      title = "English",
      required = true,
      reveal = true,
      placeholder = "e.g. cat",
      help = "Meaning shown after the card is revealed",
    },
    {
      key = "notes",
      label = "Notes: ",
      title = "Notes",
      reveal = true,
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
  aliases = {
    chinese = { "hanzi", "word" },
    pinyin = { "reading" },
  },
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
      placeholder = "e.g. māo",
      help = "Pronunciation with tone marks or numbers",
    },
    {
      key = "english",
      label = "English: ",
      title = "English",
      required = true,
      reveal = true,
      placeholder = "e.g. cat",
      help = "Meaning shown after the card is revealed",
    },
    {
      key = "notes",
      label = "Notes: ",
      title = "Notes",
      reveal = true,
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

function M.only(...)
  local languages = {}
  for _, name in ipairs({ ... }) do
    if M[name] then
      languages[name] = vim.deepcopy(M[name])
    end
  end
  return languages
end

return M

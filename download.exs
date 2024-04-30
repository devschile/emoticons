#!/usr/bin/env elixir
# CODE UNDER MIT License
Mix.install([
  {:jason, "~> 1.4"}
])

require Logger

# ["data/emoji_p1.json"]
Path.wildcard(Path.join(["data", "*.json"]))
|> Enum.sort()
|> Enum.flat_map(fn file ->
  Logger.info("Processing File")
  Logger.debug(file)

  File.read!(file)
  |> Jason.decode!(keys: :atoms)
  |> then(& &1.emoji)
  |> Enum.filter(fn item ->
    # Avoid  slack default images
    case item.url do
      "https://emoji.slack-edge.com" <> _ -> true
      _ -> false
    end
  end)
  |> Enum.sort_by(fn item ->
    item.created
  end)
  |> Enum.map(fn item ->
    Task.async(fn ->
      Logger.info("Processing Item: #{item.name}")

      date = DateTime.from_unix!(item.created)

      directory = "emoticons"
      File.mkdir_p!(directory)
      path = Path.join([directory, Path.basename(item.url)])
      github = "https://raw.githubusercontent.com/devschile/emoticons/main/#{path}"

      # Download file
      if !File.exists?(path) do
        Logger.info("Downloading File")
        Logger.debug(item.url)
        System.cmd("wget", ["-P", directory, "-c", item.url])
      end

      %{
        filename: Path.basename(path),
        directory: directory,
        path: path,
        url: github,
        author: item.user_display_name,
        date: date,
        name: item.name,
        id: ":#{item.name}:"
      }
    end)
  end)
end)
|> Task.await_many(:infinity)
|> tap(fn items ->
  Logger.info("Writing emoticons.json")

  emoticons =
    Enum.reduce(items, %{}, fn item, acc ->
      Map.merge(acc, %{"#{item.id}": item})
    end)

  File.write!("emoticons.json", Jason.encode!(emoticons), [:write])
end)
|> tap(fn items ->
  Logger.info("Writing Markdown")

  output =
    """
    |#|Emoticon|Nombre|Autor|Fecha|
    |---|---|---|---|---|
    """

  table =
    items
    |> Enum.with_index(fn item, index ->
      """
      |**#{index}**|![#{item.id}](#{item.url})|#{item.id}|#{item.author}|#{item.date}|
      """
    end)

  output = output <> Enum.join(table)

  File.read!("README.template.md")
  |> String.replace("EMOTICONS", output)
  |> then(&File.write!("README.md", &1, [:write]))
end)
|> tap(fn items ->
  Logger.info("All Done!")
  Logger.debug("Processed #{Enum.count(items)} items")
end)

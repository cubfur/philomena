defmodule Philomena.Images.SearchIndex do
  @behaviour PhilomenaQuery.Search.Index

  @impl true
  def index_name do
    "images"
  end

  @impl true
  def mapping do
    %{
      settings: %{
        index: %{
          number_of_shards: 5,
          max_result_window: 10_000_000
        }
      },
      mappings: %{
        dynamic: false,
        properties: %{
          animated: %{type: "boolean"},
          anonymous: %{type: "boolean"},
          aspect_ratio: %{type: "float"},
          comment_count: %{type: "integer"},
          commenters: %{type: "keyword"},
          created_at: %{type: "date"},
          deleted_by_user: %{type: "keyword"},
          deleted_by_user_id: %{type: "keyword"},
          deletion_reason: %{type: "text", analyzer: "snowball"},
          description: %{type: "text", analyzer: "snowball"},
          downvoter_ids: %{type: "keyword"},
          downvoters: %{type: "keyword"},
          downvotes: %{type: "integer"},
          duplicate_id: %{type: "integer"},
          duration: %{type: "float"},
          faves: %{type: "integer"},
          favourited_by_user_ids: %{type: "keyword"},
          favourited_by_users: %{type: "keyword"},
          file_name: %{type: "keyword"},
          fingerprint: %{type: "keyword"},
          first_seen_at: %{type: "date"},
          fps: %{type: "float"},
          frames: %{type: "integer"},
          height: %{type: "integer"},
          hidden_by_user_ids: %{type: "keyword"},
          hidden_by_users: %{type: "keyword"},
          hidden_from_users: %{type: "keyword"},
          id: %{type: "integer"},
          ip: %{type: "ip"},
          mime_type: %{type: "keyword"},
          orig_sha512_hash: %{type: "keyword"},
          original_format: %{type: "keyword"},
          pixels: %{type: "integer"},
          processed: %{type: "boolean"},
          score: %{type: "integer"},
          size: %{type: "integer"},
          orig_size: %{type: "integer"},
          sha512_hash: %{type: "keyword"},
          source_url: %{type: "keyword"},
          source_count: %{type: "integer"},
          tag_count: %{type: "integer"},
          tag_ids: %{type: "keyword"},
          tags: %{type: "text", analyzer: "keyword"},
          thumbnails_generated: %{type: "boolean"},
          true_uploader: %{type: "keyword"},
          true_uploader_id: %{type: "keyword"},
          updated_at: %{type: "date"},
          uploader: %{type: "keyword"},
          uploader_id: %{type: "keyword"},
          upvoter_ids: %{type: "keyword"},
          upvoters: %{type: "keyword"},
          upvotes: %{type: "integer"},
          user_id: %{type: "keyword"},
          width: %{type: "integer"},
          wilson_score: %{type: "float"},
          galleries: %{
            type: "nested",
            properties: %{
              id: %{type: "integer"},
              position: %{type: "integer"}
            }
          },
          gallery_id: %{type: "keyword"},
          gallery_position: %{type: "object", enabled: false},
          namespaced_tags: %{
            properties: %{
              name: %{type: "keyword"},
              name_in_namespace: %{type: "keyword"},
              namespace: %{type: "keyword"}
            }
          },
          approved: %{type: "boolean"},
          error_tag_count: %{type: "integer"},
          rating_tag_count: %{type: "integer"},
          origin_tag_count: %{type: "integer"},
          character_tag_count: %{type: "integer"},
          oc_tag_count: %{type: "integer"},
          species_tag_count: %{type: "integer"},
          body_type_tag_count: %{type: "integer"},
          content_fanmade_tag_count: %{type: "integer"},
          content_official_tag_count: %{type: "integer"},
          spoiler_tag_count: %{type: "integer"}
        }
      }
    }
  end

  @impl true
  def as_json(image) do
    %{
      id: image.id,
      upvotes: image.upvotes_count,
      downvotes: image.downvotes_count,
      score: image.score,
      faves: image.faves_count,
      comment_count: image.comments_count,
      width: image.image_width,
      height: image.image_height,
      pixels: image.image_width * image.image_height,
      size: image.image_size,
      orig_size: image.image_orig_size,
      animated: image.image_is_animated,
      duration: if(image.image_is_animated, do: image.image_duration, else: 0),
      tag_count: length(image.tags),
      aspect_ratio: image.image_aspect_ratio,
      wilson_score: wilson_score(image),
      created_at: image.created_at,
      updated_at: image.updated_at,
      first_seen_at: image.first_seen_at,
      ip: image.ip |> to_string,
      tag_ids: image.tags |> Enum.map(& &1.id),
      mime_type: image.image_mime_type,
      uploader: if(!!image.user and !image.anonymous, do: String.downcase(image.user.name)),
      true_uploader: if(!!image.user, do: String.downcase(image.user.name)),
      source_url: image.sources |> Enum.map(&String.downcase(&1.source)),
      source_count: length(image.sources),
      file_name: image.image_name,
      original_format: image.image_format,
      processed: image.processed,
      thumbnails_generated: image.thumbnails_generated,
      fingerprint: image.fingerprint,
      uploader_id: if(!!image.user_id and !image.anonymous, do: image.user_id),
      true_uploader_id: image.user_id,
      orig_sha512_hash: image.image_orig_sha512_hash,
      sha512_hash: image.image_sha512_hash,
      hidden_from_users: image.hidden_from_users,
      anonymous: image.anonymous,
      description: image.description,
      deletion_reason: image.deletion_reason,
      favourited_by_user_ids: image.favers |> Enum.map(& &1.id),
      hidden_by_user_ids: image.hiders |> Enum.map(& &1.id),
      upvoter_ids: image.upvoters |> Enum.map(& &1.id),
      downvoter_ids: image.downvoters |> Enum.map(& &1.id),
      deleted_by_user_id: image.deleter_id,
      duplicate_id: image.duplicate_id,
      galleries:
        image.gallery_interactions |> Enum.map(&%{id: &1.gallery_id, position: &1.position}),
      namespaced_tags: %{
        name: image.tags |> Enum.flat_map(&([&1] ++ &1.aliases)) |> Enum.map(& &1.name),
        name_in_namespace:
          image.tags |> Enum.flat_map(&([&1] ++ &1.aliases)) |> Enum.map(& &1.name_in_namespace)
      },
      gallery_id: Enum.map(image.gallery_interactions, & &1.gallery_id),
      gallery_position: Map.new(image.gallery_interactions, &{&1.gallery_id, &1.position}),
      favourited_by_users: image.favers |> Enum.map(&String.downcase(&1.name)),
      hidden_by_users: image.hiders |> Enum.map(&String.downcase(&1.name)),
      upvoters: image.upvoters |> Enum.map(&String.downcase(&1.name)),
      downvoters: image.downvoters |> Enum.map(&String.downcase(&1.name)),
      deleted_by_user: if(!!image.deleter, do: image.deleter.name),
      approved: image.approved,
      error_tag_count: Enum.count(image.tags, &(&1.category == "error")),
      rating_tag_count: Enum.count(image.tags, &(&1.category == "rating")),
      origin_tag_count: Enum.count(image.tags, &(&1.category == "origin")),
      character_tag_count: Enum.count(image.tags, &(&1.category == "character")),
      oc_tag_count: Enum.count(image.tags, &(&1.category == "oc")),
      species_tag_count: Enum.count(image.tags, &(&1.category == "species")),
      body_type_tag_count: Enum.count(image.tags, &(&1.category == "body-type")),
      content_fanmade_tag_count: Enum.count(image.tags, &(&1.category == "content-fanmade")),
      content_official_tag_count: Enum.count(image.tags, &(&1.category == "content-official")),
      spoiler_tag_count: Enum.count(image.tags, &(&1.category == "spoiler"))
    }
  end

  def user_name_update_by_query(old_name, new_name) do
    old_name = String.downcase(old_name)
    new_name = String.downcase(new_name)

    %{
      query: %{
        bool: %{
          should: [
            %{term: %{uploader: old_name}},
            %{term: %{true_uploader: old_name}},
            %{term: %{deleted_by_user: old_name}},
            %{term: %{favourited_by_users: old_name}},
            %{term: %{hidden_by_users: old_name}},
            %{term: %{upvoters: old_name}},
            %{term: %{downvoters: old_name}}
          ]
        }
      },
      replacements: [
        %{path: ["uploader"], old: old_name, new: new_name},
        %{path: ["true_uploader"], old: old_name, new: new_name},
        %{path: ["deleted_by_user"], old: old_name, new: new_name}
      ],
      set_replacements: [
        %{path: ["favourited_by_users"], old: old_name, new: new_name},
        %{path: ["hidden_by_users"], old: old_name, new: new_name},
        %{path: ["upvoters"], old: old_name, new: new_name},
        %{path: ["downvoters"], old: old_name, new: new_name}
      ]
    }
  end

  def wilson_score(%{upvotes_count: upvotes, downvotes_count: downvotes}) when upvotes > 0 do
    # Population size
    n = (upvotes + downvotes) / 1

    # Success proportion
    p_hat = upvotes / n

    # z and z^2 values for CI upper 99.5%
    z = 2.57583
    z2 = 6.634900189

    (p_hat + z2 / (2 * n) - z * :math.sqrt((p_hat * (1 - p_hat) + z2 / (4 * n)) / n)) /
      (1 + z2 / n)
  end

  def wilson_score(_), do: 0
end

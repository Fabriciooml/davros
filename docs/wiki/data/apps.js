window.WIKI_APPS = {
  "apps": [
    {
      "category": "media",
      "description": "Request portal for audiobooks. Approved requests are searched and imported through Chaptarr.",
      "hosts": [
        {
          "host": "audiobookrequest.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "markbeep/audiobookrequest",
          "tag": "1.11.0"
        }
      ],
      "lan": true,
      "name": "audiobookrequest",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "audiobookrequest-config",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Audiobook library and player with progress sync. Reads the audiobooks Chaptarr imports.",
      "hosts": [
        {
          "host": "audiobooks.<domain>",
          "visibility": "public"
        },
        {
          "host": "audiobookshelf.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/advplyr/audiobookshelf",
          "tag": "2.37.2"
        }
      ],
      "lan": true,
      "name": "audiobookshelf",
      "namespace": "audiobookshelf",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "audiobookshelf-config",
          "size": "1Gi"
        },
        {
          "name": "audiobookshelf-metadata",
          "size": "5Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Subtitle manager for Sonarr and Radarr libraries.",
      "hosts": [
        {
          "host": "bazarr.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/hotio/bazarr",
          "tag": "release-1.6.0"
        }
      ],
      "lan": true,
      "name": "bazarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "bazarr-config",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Readarr-style book manager (beta). Searches through Prowlarr, downloads with qBittorrent, imports audiobooks for Audiobookshelf and hardlinks ebooks into the CWA ingest folder.",
      "hosts": [
        {
          "host": "chaptarr.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "chaptarr/chaptarr",
          "tag": "0.9.965"
        }
      ],
      "lan": true,
      "name": "chaptarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "chaptarr-config",
          "size": "2Gi"
        }
      ]
    },
    {
      "category": "apps",
      "description": "Tunnel client exposing selected apps publicly.",
      "hosts": [],
      "images": [
        {
          "pinned": true,
          "repo": "cloudflare/cloudflared",
          "tag": "2026.2.0"
        }
      ],
      "lan": false,
      "name": "cloudflared",
      "namespace": "cloudflared",
      "public": false,
      "stateful": false,
      "storage": []
    },
    {
      "category": "own apps",
      "description": "Comida di Buteco tracker. Own app; follows new image builds automatically.",
      "hosts": [
        {
          "host": "butecos.<domain>",
          "visibility": "public"
        },
        {
          "host": "comida.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": false,
          "repo": "ghcr.io/fabriciooml/comida_di_buteco_tracker",
          "tag": "main"
        }
      ],
      "lan": true,
      "name": "comida",
      "namespace": "comida",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "comida-data",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Syncs quality profiles and custom formats into Sonarr and Radarr on a schedule.",
      "hosts": [],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/raydak-labs/configarr",
          "tag": "1.30.2"
        }
      ],
      "lan": false,
      "name": "configarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "configarr-repos",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "data",
      "description": "CouchDB backing the Obsidian live-sync vault.",
      "hosts": [
        {
          "host": "obsidian.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "couchdb",
          "tag": "3.5.1"
        }
      ],
      "lan": true,
      "name": "couchdb",
      "namespace": "couchdb",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "couchdb-data",
          "size": "2Gi"
        },
        {
          "name": "couchdb-etc",
          "size": "10Mi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Calibre-Web Automated: ebook library with OPDS and KOReader sync. Imports whatever lands in its ingest folder.",
      "hosts": [
        {
          "host": "books.<domain>",
          "visibility": "public"
        },
        {
          "host": "cwa.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "crocodilestick/calibre-web-automated",
          "tag": "v4.0.8"
        }
      ],
      "lan": true,
      "name": "cwa",
      "namespace": "cwa",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "cwa-config",
          "size": "2Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Cloudflare-challenge solver proxy used by Prowlarr.",
      "hosts": [],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/flaresolverr/flaresolverr",
          "tag": "v3.5.0"
        }
      ],
      "lan": false,
      "name": "flaresolverr",
      "namespace": "arr",
      "public": false,
      "stateful": false,
      "storage": []
    },
    {
      "category": "apps",
      "description": "LAN start page (gethomepage) with a tile and status dot for every app, plus live widgets where an API key is set. Config lives as files in kubernetes/apps/homepage/config; LAN only.",
      "hosts": [
        {
          "host": "home.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/gethomepage/homepage",
          "tag": "v2.7.0"
        }
      ],
      "lan": true,
      "name": "homepage",
      "namespace": "homepage",
      "public": false,
      "stateful": false,
      "storage": []
    },
    {
      "category": "media",
      "description": "Media server for movies and shows with GPU transcoding.",
      "hosts": [
        {
          "host": "jellyfin.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "jellyfin/jellyfin",
          "tag": "10.11.8"
        }
      ],
      "lan": true,
      "name": "jellyfin",
      "namespace": "jellyfin",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "jellyfin-config",
          "size": "10Gi"
        }
      ]
    },
    {
      "category": "data",
      "description": "Single-broker Apache Kafka with a Kafka UI for browsing topics.",
      "hosts": [
        {
          "host": "kafka-ui.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "apache/kafka",
          "tag": "3.7.0"
        },
        {
          "pinned": true,
          "repo": "provectuslabs/kafka-ui",
          "tag": "digest"
        }
      ],
      "lan": true,
      "name": "kafka",
      "namespace": "kafka",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "kafka-data",
          "size": "5Gi"
        }
      ]
    },
    {
      "category": "own apps",
      "description": "Nosso Mapa: shared map app, frontend plus backend. Own app; follows new image builds.",
      "hosts": [
        {
          "host": "mapa.<domain>",
          "visibility": "public"
        },
        {
          "host": "mapa.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": false,
          "repo": "ghcr.io/fabriciooml/nosso-mapa-backend",
          "tag": "main"
        },
        {
          "pinned": false,
          "repo": "ghcr.io/fabriciooml/nosso-mapa-frontend",
          "tag": "main"
        }
      ],
      "lan": true,
      "name": "mapa",
      "namespace": "mapa",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "mapa-data",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "apps",
      "description": "Recipe manager and meal planner.",
      "hosts": [
        {
          "host": "mealie.<domain>",
          "visibility": "public"
        },
        {
          "host": "mealie.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/mealie-recipes/mealie",
          "tag": "v3.16.0"
        }
      ],
      "lan": true,
      "name": "mealie",
      "namespace": "mealie",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "mealie-data",
          "size": "2Gi"
        }
      ]
    },
    {
      "category": "own apps",
      "description": "muad_dib. Own app; follows new image builds automatically.",
      "hosts": [
        {
          "host": "muad-dib.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": false,
          "repo": "ghcr.io/fabriciooml/muad_dib",
          "tag": "main"
        }
      ],
      "lan": true,
      "name": "muad-dib",
      "namespace": "muad-dib",
      "public": false,
      "stateful": false,
      "storage": []
    },
    {
      "category": "media",
      "description": "Seerr request portal: household asks for movies and shows here.",
      "hosts": [
        {
          "host": "requester.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/seerr-team/seerr",
          "tag": "v3.1.0"
        }
      ],
      "lan": true,
      "name": "overseerr",
      "namespace": "overseerr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "overseerr-config",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Media server for movies and shows.",
      "hosts": [
        {
          "host": "plex.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "plexinc/pms-docker",
          "tag": "1.43.0.10492-121068a07"
        }
      ],
      "lan": true,
      "name": "plex",
      "namespace": "plex",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "plex-config",
          "size": "10Gi"
        }
      ]
    },
    {
      "category": "data",
      "description": "PostgreSQL 16 with pgAdmin for administration.",
      "hosts": [
        {
          "host": "pgadmin.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "dpage/pgadmin4",
          "tag": "digest"
        },
        {
          "pinned": true,
          "repo": "postgres",
          "tag": "16-alpine"
        }
      ],
      "lan": true,
      "name": "postgres",
      "namespace": "postgres",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "pgadmin-data",
          "size": "1Gi"
        },
        {
          "name": "postgres-data",
          "size": "5Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Indexer manager feeding Sonarr and Radarr.",
      "hosts": [
        {
          "host": "prowlarr.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/hotio/prowlarr",
          "tag": "release-2.5.2.5491"
        }
      ],
      "lan": true,
      "name": "prowlarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "prowlarr-config",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Torrent client. Shares the data pool with the arr apps for hardlinked imports.",
      "hosts": [
        {
          "host": "torrent.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/hotio/qbittorrent",
          "tag": "release-5.2.3"
        }
      ],
      "lan": true,
      "name": "qbittorrent",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "qbittorrent-config",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "media",
      "description": "Movie collection manager.",
      "hosts": [
        {
          "host": "radarr.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/hotio/radarr",
          "tag": "release-6.3.0.10514"
        }
      ],
      "lan": true,
      "name": "radarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "radarr-config",
          "size": "2Gi"
        }
      ]
    },
    {
      "category": "own apps",
      "description": "samsa. Own app; follows new image builds automatically.",
      "hosts": [
        {
          "host": "samsa.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": false,
          "repo": "ghcr.io/fabriciooml/samsa",
          "tag": "latest"
        }
      ],
      "lan": true,
      "name": "samsa",
      "namespace": "samsa",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "samsa-keys",
          "size": "100Mi"
        }
      ]
    },
    {
      "category": "media",
      "description": "TV series collection manager. Hardlinks imports from qBittorrent.",
      "hosts": [
        {
          "host": "sonarr.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "ghcr.io/hotio/sonarr",
          "tag": "release-4.0.19.2979"
        }
      ],
      "lan": true,
      "name": "sonarr",
      "namespace": "arr",
      "public": false,
      "stateful": true,
      "storage": [
        {
          "name": "sonarr-config",
          "size": "2Gi"
        }
      ]
    },
    {
      "category": "apps",
      "description": "Self-hosted Bitwarden-compatible password manager.",
      "hosts": [
        {
          "host": "vault.<domain>",
          "visibility": "public"
        },
        {
          "host": "vault.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "vaultwarden/server",
          "tag": "1.37.4"
        }
      ],
      "lan": true,
      "name": "vaultwarden",
      "namespace": "vaultwarden",
      "public": true,
      "stateful": true,
      "storage": [
        {
          "name": "vaultwarden-data",
          "size": "1Gi"
        }
      ]
    },
    {
      "category": "apps",
      "description": "This wiki. nginx serves docs/wiki straight from the repo; git-sync pulls main every minute. LAN only.",
      "hosts": [
        {
          "host": "wiki.local.<domain>",
          "visibility": "lan"
        }
      ],
      "images": [
        {
          "pinned": true,
          "repo": "nginxinc/nginx-unprivileged",
          "tag": "1.29-alpine"
        },
        {
          "pinned": true,
          "repo": "registry.k8s.io/git-sync/git-sync",
          "tag": "v4.4.0"
        }
      ],
      "lan": true,
      "name": "wiki",
      "namespace": "wiki",
      "public": false,
      "stateful": false,
      "storage": []
    }
  ]
};

module.exports =
  hostings: [
    regions:
      europe:
        name: "Europe"
        localizedName:
          fr: "Europe"
        zones:
          switzerland:
            name: "Switzerland"
            localizedName:
              fr: "Suisse"
            hostings:
              core1:
                url: "https://my-hosting-provider.ch"
                name: "Pilot core server"
                description: "The single PoC core server"
                available: true,
                availableCore: "https://my-core.ch",
  ]
  platforms: [
    "pryv.me"
  ]
  appids: [
    "default"
  ],
  invitationTokens: [
    "o3in4o2"
  ],
  languageCodes: [
    "en",
    "fr"
  ],
  referers: [
    "hospital-A"
  ],
  servers: [
    "core1.pryv.me"
    "core2.pryv.me"
  ],
  usersCount:
    "core1.pryv.me": 1337
    "core2.pryv.me": 42
  ,
  apps: [
    id: "pryv-csv-importer"
    displayName: "CSV Importer"
    description: "Import existing data from CSV files"
    iconURL: "https://pryv.github.io/static-web/apps/pryv-csv-importer/icon512.png"
    appURL: "http://pryv.github.io/dev-tools/csv-importer"
    active: false
    onboarding: false
    category: "Other"
    support: [
      "iPad"
      "iPhone"
      "Web"
    ]
    settingsPageURL: "http://pryv.github.io/dev-tools/csv-importer"
  ,
    id: "ifttt-all"
    displayName: "IFTTT"
    description: "Connect Pryv to over 100 other products and services with Pryv Recipes on IFTTT"
    iconURL: "https://pryv.github.io/static-web/apps/ifttt-all/icon512.png"
    appURL: "https://ifttt.com/pryv"
    active: false
    onboarding: false
    category: "Other"
    support: [
      "iPad"
      "iPhone"
      "Web"
    ]
    settingsPageURL: "https://ifttt.com/pryv"
  ]

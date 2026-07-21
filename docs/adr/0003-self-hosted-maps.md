# ADR-0003: self-hosted OSM stack

Статус: принято.

Клиент использует MapLibre и first-party style URL. Векторные тайлы генерируются из выбранного OSM PBF в MBTiles/PMTiles, Martin раздаёт их внутри сети, Nginx публикует versioned assets. Поиск идёт API → private Nominatim; прямой доступ mobile к geocoder отсутствует. Routing представлен интерфейсом и выключен в MVP. Обязательная атрибуция OSM встроена в UI и style metadata.

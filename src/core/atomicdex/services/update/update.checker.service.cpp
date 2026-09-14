/******************************************************************************
 * Copyright © 2013-2022 The Komodo Platform Developers.                      *
 *                                                                            *
 * See the AUTHORS, DEVELOPER-AGREEMENT and LICENSE files at                  *
 * the top-level directory of this distribution for the individual copyright  *
 * holder information and the developer policies on copyright and licensing.  *
 *                                                                            *
 * Unless otherwise agreed in a custom licensing agreement, no part of the    *
 * Software is provided "AS IS", without warranty of any kind.                *
 *                                                                            *
 * Removal or modification of this copyright notice is prohibited.            *
 *                                                                            *
 ******************************************************************************/

#include <QJsonDocument>

#include <boost/algorithm/string/replace.hpp>
#include <nlohmann/json.hpp>

#include "atomicdex/services/update/update.checker.service.hpp"
#include "atomicdex/utilities/http.utilities.hpp"
#include "atomicdex/version/version.hpp"

namespace
{
    //! The 0.6.1-era update endpoint (komodo.earth/adexproversion) no longer
    //! answers, so releases are tracked via the upstream GitHub releases API
    //! instead. Response fields are mapped onto the same result shape the
    //! NewUpdateModal expects; GitHub has no "required" concept, so any
    //! newer tag maps to "recommended".
    constexpr const char* g_releases_endpoint = "https://api.github.com";
    constexpr const char* g_releases_repo     = "GLEECBTC/komodo-wallet-desktop";
    atomic_dex::http::client_config g_releases_cfg{[]() {
        atomic_dex::http::client_config cfg;
        cfg.set_validate_certificates(false);
        cfg.set_timeout(std::chrono::seconds(10));
        return cfg;
    }()};
    t_http_client_ptr g_releases_client{std::make_unique<t_http_client>((g_releases_endpoint), g_releases_cfg)};

    async::task<t_http_response>
    async_check_retrieve()
    {
        return async::spawn([]() {
            t_http_request req;
            req.set_method(http_method::GET);
            req.set_request_uri(std::string("/repos/") + g_releases_repo + "/releases/latest");
            req.headers().set_header("User-Agent", "komodo-wallet-desktop");
            req.headers().set_header("Accept", "application/vnd.github+json");
            return g_releases_client->request(req).get();
        });
    }

    std::string
    strip_leading_v(std::string version)
    {
        if (!version.empty() && (version[0] == 'v' || version[0] == 'V'))
        {
            version.erase(0, 1);
        }
        return version;
    }

    nlohmann::json
    get_update_info_rpc(t_http_response resp_http)
    {
        using namespace std::string_literals;
        nlohmann::json resp;
        nlohmann::json result;
        if (resp_http.status_code() != 200)
        {
            result["status"] = (QObject::tr("Cannot reach the endpoint: ") + g_releases_endpoint).toStdString();
        }
        else
        {
            resp = nlohmann::json::parse(resp_http.extract_string(true).get());
        }
        result["rpcCode"]        = resp_http.status_code();
        result["currentVersion"] = atomic_dex::get_raw_version();
        if (resp_http.status_code() == 200)
        {
            bool        update_needed       = false;
            std::string current_version_str = strip_leading_v(atomic_dex::get_raw_version());
            std::string endpoint_version    = strip_leading_v(resp.at("tag_name").get<std::string>());
            boost::algorithm::replace_all(current_version_str, ".", "");
            boost::algorithm::replace_all(endpoint_version, ".", "");
            boost::algorithm::trim_left_if(current_version_str, boost::is_any_of("0"));
            boost::algorithm::trim_left_if(endpoint_version, boost::is_any_of("0"));
            update_needed = std::stoi(current_version_str) < std::stoi(endpoint_version);
            result["updateNeeded"] = update_needed;
            result["newVersion"]   = resp.at("tag_name").get<std::string>();
            result["downloadUrl"]  = resp.value("html_url", "");
            result["changelog"]    = (resp.contains("body") && resp.at("body").is_string()) ? resp.at("body").get<std::string>() : "";
            result["status"]       = update_needed ? "recommended" : "up-to-date";
        }
        SPDLOG_INFO(
            "Update check complete: currentVersion={}, newVersion={}, updateNeeded={}, status={}", result.value("currentVersion", ""),
            result.value("newVersion", ""), result.value("updateNeeded", false), result.value("status", ""));
        return result;
    }
} // namespace

namespace atomic_dex
{
    update_checker_service::update_checker_service(entt::registry& registry, QObject* parent) : QObject(parent), system(registry)
    {
        m_update_clock = std::chrono::high_resolution_clock::now();
        m_update_info  = nlohmann::json::object();
        fetch_update_info();
    }

    void
    update_checker_service::update()
    {
        using namespace std::chrono_literals;

        const auto now = std::chrono::high_resolution_clock::now();
        const auto s   = std::chrono::duration_cast<std::chrono::seconds>(now - m_update_clock);
        if (s >= 1h)
        {
            fetch_update_info();
            m_update_clock = std::chrono::high_resolution_clock::now();
        }
    }

    void
    update_checker_service::fetch_update_info()
    {
        if (is_fetching)
            return;
        is_fetching = true;
        emit isFetchingChanged();
        async_check_retrieve().then([this](async::task<t_http_response> previous_task) {
            try
            {
                this->m_update_info = get_update_info_rpc(previous_task.get());
            }
            catch (const std::exception& e)
            {
                SPDLOG_ERROR("exception in fetch_update_info: {}", e.what());
                nlohmann::json result;
                result["rpcCode"]        = -1;
                result["currentVersion"] = atomic_dex::get_raw_version();
                result["status"]         = e.what();
                this->m_update_info      = result;
            }
            is_fetching = false;
            emit isFetchingChanged();
            emit updateInfoChanged();
        });
    }

    QVariant
    update_checker_service::get_update_info() const
    {
        nlohmann::json info = *m_update_info;
        QJsonDocument  doc  = QJsonDocument::fromJson(QString::fromStdString(info.dump()).toUtf8());
        return doc.toVariant();
    }
} // namespace atomic_dex

/******************************************************************************
 * Copyright © 2013-2024 The Komodo Platform Developers.                      *
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

//! Deps
#include <nlohmann/json.hpp>

//! Our project
#include "atomicdex/events/events.hpp"
#include "atomicdex/services/internet/internet.checker.service.hpp"
#include "atomicdex/utilities/http.utilities.hpp"

namespace
{
    constexpr const char* g_time_endpoint = "https://time.now";
    atomic_dex::http::client_config g_probe_cfg{[]() {
        atomic_dex::http::client_config cfg;
        cfg.set_validate_certificates(false);
        cfg.set_timeout(std::chrono::seconds(5));
        return cfg;
    }()};

    t_http_client_ptr g_time_client = std::make_unique<t_http_client>((g_time_endpoint), g_probe_cfg);

    async::task<t_http_response>
    async_probe(t_http_client_ptr& client, const std::string& uri)
    {
        return async::spawn([&client, uri]() {
            t_http_request req;
            req.set_method(http_method::GET);
            req.set_request_uri(uri);
            return client->request(req).get();
        });
    }
} // namespace

namespace atomic_dex
{
    void
    internet_service_checker::set_internet_alive(bool internet_status)
    {
        if (internet_status != is_internet_reacheable)
        {
            is_internet_reacheable = internet_status;
            emit internetStatusChanged();
        }
    }

    bool
    internet_service_checker::is_internet_alive() const
    {
        return is_internet_reacheable.load();
    }

    double
    internet_service_checker::get_seconds_left_to_auto_retry() const
    {
        return m_timer;
    }

    void
    internet_service_checker::set_seconds_left_to_auto_retry(double time_left)
    {
        m_timer = time_left;
        emit secondsLeftToAutoRetryChanged();
    }
} // namespace atomic_dex

namespace atomic_dex
{
    internet_service_checker::internet_service_checker(entt::registry& registry, QObject* parent) : QObject(parent), system(registry)
    {
        m_update_clock = std::chrono::high_resolution_clock::now();
        retry();
    }

    void
    internet_service_checker::retry()
    {
        m_update_clock = std::chrono::high_resolution_clock::now();
        set_seconds_left_to_auto_retry(60.0);
        this->fetch_internet_connection();
    }

    void
    internet_service_checker::update()
    {
        using namespace std::chrono_literals;

        const auto now = std::chrono::high_resolution_clock::now();
        const auto s   = std::chrono::duration_cast<std::chrono::seconds>(now - m_update_clock);
        set_seconds_left_to_auto_retry(60.0 - s.count());
        if (s >= 60s)
        {
            this->fetch_internet_connection();
            m_update_clock = std::chrono::high_resolution_clock::now();
            set_seconds_left_to_auto_retry(60.0);
        }
    }

    void
    internet_service_checker::treat_probe_result(bool ok, const std::string& endpoint, unsigned int generation)
    {
        //! Ignore stale generations: only the latest round may flip the flag,
        //! so a slow success still wins over an earlier fast failure.
        if (generation != m_probe_generation.load())
        {
            return;
        }
        if (ok)
        {
            m_probe_succeeded = true;
            SPDLOG_INFO("Connectivity is true for the endpoint: {}", endpoint);
            this->set_internet_alive(true);
        }
        else if (!m_probe_succeeded.load())
        {
            SPDLOG_WARN("Connectivity is false for: {}", endpoint);
            this->dispatcher_.trigger<endpoint_nonreacheable>(endpoint_nonreacheable{.base_uri = endpoint});
            this->set_internet_alive(false);
        }
    }

    void
    internet_service_checker::fetch_internet_connection()
    {
        const unsigned int generation = ++m_probe_generation;
        m_probe_succeeded             = false;

        async_probe(g_time_client, "/developer/api/timezone/UTC")
            .then([this, generation](async::task<t_http_response> previous_task) {
                try
                {
                    t_http_response resp = previous_task.get();
                    this->treat_probe_result(resp.status_code() == 200, g_time_endpoint, generation);
                }
                catch (const std::exception& e)
                {
                    SPDLOG_WARN("internet probe error for {}: {}", g_time_endpoint, e.what());
                    this->treat_probe_result(false, g_time_endpoint, generation);
                }
            });
    }
} // namespace atomic_dex
